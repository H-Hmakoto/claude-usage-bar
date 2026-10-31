import Cocoa
import WebKit
import SwiftUI
import ServiceManagement

// Shows the Claude 5-hour / weekly usage percentages in the macOS menu bar.
// It reads the claude.ai Settings > Usage page in an in-app web view that the user signs in to
// themselves. No Claude API tokens or Keychain items are used. Unofficial; not affiliated with Anthropic.

let isKorean = (Locale.preferredLanguages.first ?? "").hasPrefix("ko")
func L(_ ko: String, _ en: String) -> String { isKorean ? ko : en }

// MARK: - Reading claude.ai Settings > Usage (web view, user signs in)

struct WebItem { let label: String; let percent: Int; let reset: String?; var kind: String = "" }

func parseISODate(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    // Microsecond fractions ("...00.570606+00:00") are not always accepted; drop them and retry.
    return f.date(from: s.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression))
}

func resetText(_ raw: Date) -> String {
    // The API reports times like 07:59:59; round to the nearest minute so they read as 8:00.
    let d = Date(timeIntervalSinceReferenceDate: (raw.timeIntervalSinceReferenceDate / 60).rounded() * 60)
    let f = DateFormatter()
    f.locale = Locale.current
    f.setLocalizedDateFormatFromTemplate(d.timeIntervalSinceNow < 86400 ? "jmm" : "EEE jmm")
    return L("\(f.string(from: d))에 초기화", "Resets \(f.string(from: d))")
}

/// Parses the JSON the usage page itself loads (/api/organizations/<id>/usage). It is language independent and
/// includes model-specific weekly limits (e.g. Fable) that the page text does not show.
func parseUsageJSON(_ s: String) -> (cards: [WebItem], breakdown: [WebItem])? {
    guard let data = s.data(using: .utf8),
          let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let limits = o["limits"] as? [[String: Any]] else { return nil }
    var cards: [WebItem] = []
    for l in limits {
        guard let kind = l["kind"] as? String, let pct = (l["percent"] as? NSNumber)?.intValue else { continue }
        let reset = (l["resets_at"] as? String).flatMap(parseISODate).map(resetText)
        let scope = l["scope"] as? [String: Any]
        let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
        let label: String
        switch kind {
        case "session": label = L("현재 세션 (5시간)", "Current session (5h)")
        case "weekly_all": label = L("이번 주 · 모든 모델", "This week · all models")
        case "weekly_scoped": label = L("이번 주 · ", "This week · ") + (model ?? L("특정 모델", "scoped"))
        default: label = kind.replacingOccurrences(of: "_", with: " ")
        }
        cards.append(WebItem(label: label, percent: pct, reset: reset, kind: kind))
    }
    guard !cards.isEmpty else { return nil }
    var breakdown: [WebItem] = []
    if let rows = (o["seven_day_breakdown"] as? [String: Any])?["rows"] as? [[String: Any]] {
        for r in rows {
            if let n = r["display_name"] as? String, let p = (r["percent"] as? NSNumber)?.intValue {
                breakdown.append(WebItem(label: n, percent: p, reset: nil))
            }
        }
    }
    return (cards, breakdown)
}

func parsePlan(_ text: String) -> String? {
    let re = try! NSRegularExpression(pattern: "^(Free|Pro|Max(\\s*\\(?\\d+x\\)?)?|Team|Enterprise)$", options: .caseInsensitive)
    func isPlan(_ l: String) -> Bool { re.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil }
    let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    // The plan name is the line right under the "Usage" heading; other "Max"/"Pro" lines (menus, upsells) are ignored.
    for (i, l) in lines.enumerated() where (l == "사용량" || l == "Usage") && i + 1 < lines.count && isPlan(lines[i + 1]) {
        return lines[i + 1]
    }
    return lines.last(where: isPlan)
}

func parseUsageText(_ text: String) -> [WebItem] {
    let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    // Only lines that are just a percentage ("3% 사용됨", "3% used", or a bare "61%"), not prose like "100% of your limit".
    let pct = try! NSRegularExpression(pattern: "^(\\d{1,3})\\s*%(\\s*(사용됨|used))?$", options: .caseInsensitive)
    let resetWords = ["재설정", "초기화", "Resets", "resets", "reset"]
    var items: [WebItem] = []
    for (i, line) in lines.enumerated() {
        guard let m = pct.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r = Range(m.range(at: 1), in: line), let p = Int(line[r]) else { continue }
        var label = ""
        for j in stride(from: i - 1, through: max(0, i - 4), by: -1) {
            let c = lines[j]
            // Skip icon-only lines (tooltip glyphs etc.): a real label has at least one letter.
            let hasLetter = c.contains { $0.isLetter }
            if hasLetter && !c.contains("%") && !resetWords.contains(where: { c.contains($0) }) { label = c; break }
        }
        // The reset-time line sits directly above the percent line on claude.ai.
        var reset: String?
        if i > 0, resetWords.contains(where: { lines[i - 1].contains($0) }) { reset = lines[i - 1] }
        items.append(WebItem(label: label, percent: p, reset: reset))
    }
    return items
}

final class WebUsage: NSObject, WKNavigationDelegate {
    // Remember the page's own usage API response (no extra requests are made).
    static let hookJS = #"""
    (function(){const of=window.fetch;window.fetch=async function(...a){const r=await of.apply(this,a);
    try{const u=(typeof a[0]==='string')?a[0]:((a[0]&&a[0].url)||'');
    if(/\/api\/organizations\/[^\/]+\/usage(\?|$)/.test(u)){r.clone().text().then(t=>{if(t.indexOf('"limits"')>=0)window.__cubUsage=t;});}}catch(e){}return r;};})();
    """#
    let web: WKWebView = {
        let c = WKWebViewConfiguration()
        c.userContentController.addUserScript(WKUserScript(source: WebUsage.hookJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        return WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: c)
    }()
    let window: NSWindow
    var cards: [WebItem] = []
    var breakdown: [WebItem] = []
    var plan: String?
    var needsLogin = false { didSet {} }
    var onUpdate: (() -> Void)?
    static let url = URL(string: "https://claude.ai/settings/usage")!

    override init() {
        window = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        window.title = L("Claude 로그인 (한 번만 하면 됩니다)", "Sign in to Claude (one time only)")
        window.contentView = web
        window.isReleasedWhenClosed = false
        super.init()
        web.navigationDelegate = self
    }

    func reload() { web.load(URLRequest(url: WebUsage.url)) }
    func showWindow() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }

    func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait for the single-page app to render before reading the text.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self else { return }
            let path = self.web.url?.path ?? ""
            let was = self.needsLogin
            self.needsLogin = path.hasPrefix("/login") || path.hasPrefix("/logout")
            if self.needsLogin && !was { self.showWindow() }
            self.web.evaluateJavaScript("window.__cubUsage || ''") { json, _ in
                self.web.evaluateJavaScript("document.body.innerText") { res, _ in
                    let text = (res as? String) ?? ""
                    if !self.needsLogin {
                        if let parsed = parseUsageJSON((json as? String) ?? "") {
                            self.cards = parsed.cards
                            self.breakdown = parsed.breakdown
                        } else {
                            // Fallback: scrape the visible page text.
                            let items = parseUsageText(text)
                            self.cards = Array(items.prefix(2))
                            self.breakdown = Array(items.dropFirst(2).filter { !$0.label.isEmpty && $0.label.count < 20 })
                        }
                        self.plan = parsePlan(text)
                        if !self.cards.isEmpty { self.window.orderOut(nil) }
                    }
                    self.onUpdate?()
                }
            }
        }
    }
}


// MARK: - UI

let claudeOrange = Color(red: 0.851, green: 0.467, blue: 0.341)   // #D97757

struct Burst: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2
        for i in 0..<12 {
            let a = CGFloat(i) / 12 * 2 * .pi
            let len = R * (i % 2 == 0 ? 1.0 : 0.74)
            p.move(to: CGPoint(x: c.x + cos(a) * R * 0.2, y: c.y + sin(a) * R * 0.2))
            p.addLine(to: CGPoint(x: c.x + cos(a) * len, y: c.y + sin(a) * len))
        }
        return p
    }
}

func statusIcon() -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
        let c = NSPoint(x: r.midX, y: r.midY), R = r.width / 2 - 1
        let path = NSBezierPath()
        path.lineWidth = 1.7
        path.lineCapStyle = .round
        for i in 0..<12 {
            let a = CGFloat(i) / 12 * 2 * .pi
            let len = R * (i % 2 == 0 ? 1.0 : 0.74)
            path.move(to: NSPoint(x: c.x + cos(a) * R * 0.2, y: c.y + sin(a) * R * 0.2))
            path.line(to: NSPoint(x: c.x + cos(a) * len, y: c.y + sin(a) * len))
        }
        NSColor.black.setStroke()
        path.stroke()
        return true
    }
    img.isTemplate = true
    return img
}

final class UsageModel: ObservableObject {
    @Published var cards: [WebItem] = []
    @Published var breakdown: [WebItem] = []
    @Published var needsLogin = false
    @Published var plan: String?
    @Published var launchAtLogin = false
    @Published var updatedAt: Date?
    var onRefresh: () -> Void = {}
    var onLogin: () -> Void = {}
    var onToggleLaunch: () -> Void = {}
}

func usageColor(_ pct: Int) -> Color {
    pct >= 90 ? .red : pct >= 70 ? .orange : claudeOrange
}

struct UsageCard: View {
    let item: WebItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.label.isEmpty ? L("사용량", "Usage") : item.label).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(item.percent)%").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundColor(usageColor(item.percent))
            }
            ProgressBar(value: Double(item.percent) / 100, color: usageColor(item.percent), height: 8)
            if let r = item.reset { Text(r).font(.system(size: 11)).foregroundColor(.secondary) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
    }
}

struct ProgressBar: View {
    let value: Double, color: Color, height: CGFloat
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(color).frame(width: max(height, g.size.width * min(1, value)))
            }
        }.frame(height: height)
    }
}

struct UsageView: View {
    @ObservedObject var m: UsageModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Burst().stroke(claudeOrange, style: StrokeStyle(lineWidth: 2.4, lineCap: .round)).frame(width: 22, height: 22)
                Text(L("Claude 사용량", "Claude Usage")).font(.system(size: 15, weight: .semibold))
                if let p = m.plan {
                    Text(p).font(.system(size: 11, weight: .semibold)).foregroundColor(claudeOrange)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(claudeOrange.opacity(0.18)))
                }
                Spacer()
                Button(action: m.onRefresh) { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).foregroundColor(.secondary)
            }
            if m.needsLogin {
                VStack(spacing: 10) {
                    Text(L("claude.ai 로그인이 필요해요", "Sign in to claude.ai")).font(.system(size: 13))
                    Button(L("로그인", "Sign in"), action: m.onLogin).buttonStyle(.borderedProminent).tint(claudeOrange)
                }.frame(maxWidth: .infinity).padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
            } else if !m.cards.isEmpty {
                ForEach(Array(m.cards.enumerated()), id: \.offset) { _, c in UsageCard(item: c) }
                let rest = Array(m.breakdown.prefix(6))
                if !rest.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L("이번 주 제품별", "This week by product")).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        ForEach(Array(rest.enumerated()), id: \.offset) { _, it in
                            HStack(spacing: 8) {
                                Text(it.label).font(.system(size: 12)).frame(width: 84, alignment: .leading)
                                ProgressBar(value: Double(it.percent) / 100, color: claudeOrange.opacity(0.8), height: 5)
                                Text("\(it.percent)%").font(.system(size: 11, design: .rounded)).foregroundColor(.secondary).frame(width: 34, alignment: .trailing)
                            }
                        }
                    }.padding(.horizontal, 4)
                }
            } else {
                ProgressView().controlSize(.small).padding(20)
            }
            Divider()
            HStack {
                if let t = m.updatedAt {
                    Text(L("갱신 ", "Updated ") + t.formatted(date: .omitted, time: .standard)).font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
                Button(m.launchAtLogin ? L("자동 실행 끄기", "Don't launch at login") : L("로그인 시 자동 실행", "Launch at login"), action: m.onToggleLaunch).buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.secondary)
                Button(L("종료", "Quit")) { NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let model = UsageModel()
    let webUsage = WebUsage()
    let popover = NSPopover()

    func applicationDidFinishLaunching(_ n: Notification) {
        if let b = item.button {
            b.image = statusIcon()
            b.imagePosition = .imageLeft
            b.target = self
            b.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: UsageView(m: model))
        model.onRefresh = { [weak self] in self?.refresh() }
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        model.onToggleLaunch = { [weak self] in
            guard let self else { return }
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
            } catch { NSLog("launch-at-login failed: \(error)") }
            self.model.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        model.onLogin = { [weak self] in self?.webUsage.reload(); self?.webUsage.showWindow() }

        webUsage.onUpdate = { [weak self] in self?.render() }
        webUsage.reload()
        refresh()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.webUsage.reload() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    }

    @objc func togglePopover() {
        guard let b = item.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        refresh()
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() { webUsage.reload() }

    func render() {
        model.cards = webUsage.cards
        model.breakdown = webUsage.breakdown
        model.plan = webUsage.plan
        model.updatedAt = Date()
        model.needsLogin = webUsage.needsLogin
        let c = webUsage.cards
        let session = c.first { $0.kind == "session" } ?? c.first
        let weekly = c.first { $0.kind == "weekly_all" } ?? (c.count > 1 ? c[1] : nil)
        let text: String
        if let s = session, let w = weekly { text = "\(s.percent)% · \(w.percent)%" }
        else if webUsage.needsLogin { text = L("로그인", "Sign in") }
        else { text = "…" }
        item.button?.attributedTitle = NSAttributedString(
            string: " " + text,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()

# Claude Usage Bar

A tiny macOS menu bar app that shows your Claude **5-hour session** and **weekly** usage at a glance, so you don't have to open Settings > Usage every time.
Chat, Claude Code and Cowork share the same limits, so one percentage covers all of them.

Claude 사용량(5시간 세션 / 주간)을 메뉴바에서 바로 보여주는 작은 macOS 앱입니다.

- Menu bar: `5% · 76%` (session · weekly). Click for details, reset times, per-product breakdown and your plan.
- Refreshes every 5 minutes, when you open the popover, and when the Mac wakes up.
- English and Korean UI (follows your system language).

## How it works / privacy

The app opens `claude.ai/settings/usage` in an in-app web view and reads the page text.
You sign in once inside that web view (use **Continue with email** — Google blocks sign-in in embedded web views).

- No Claude API tokens, no Keychain access, no requests to any host other than `claude.ai`.
- Reading the page does not consume your usage limits.
- The login session (cookies) is kept by the app's web view only.
- Unofficial and not affiliated with Anthropic. It parses the visible page, so a claude.ai redesign may break it.

## Install

Requires macOS 13+.

**Download:** grab `ClaudeUsageBar.zip` from [Releases](../../releases), unzip, and move `ClaudeUsageBar.app` to `/Applications`.
The app is not notarized, so the first time: right-click the app > **Open**, or run

```bash
xattr -dr com.apple.quarantine /Applications/ClaudeUsageBar.app
```

**Build from source** (needs Xcode Command Line Tools):

```bash
git clone https://github.com/H-Hmakoto/claude-usage-bar.git
cd claude-usage-bar
./build.sh
open ClaudeUsageBar.app
```

Use the popover's **Launch at login** to start it automatically.

## Troubleshooting

- *Icon missing:* the menu bar may be full (or hidden behind the notch). Hold ⌘ and drag other icons out.
- *Shows "Sign in":* click the icon > Sign in, and log in with email.

## License

MIT

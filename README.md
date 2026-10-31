# Claude Usage Bar

A tiny macOS menu bar app that shows your Claude **5-hour session** and **weekly** usage at a glance, so you don't have to open Settings > Usage every time.
Chat, Claude Code and Cowork share the same limits, so one percentage covers all of them.

Claude 사용량(5시간 세션 / 주간)을 메뉴바에서 바로 보여주는 작은 macOS 앱입니다.

- Menu bar: `5% · 76%` (session · weekly). Click for details, reset times, per-product breakdown and your plan.
- Refreshes every 5 minutes, when you open the popover, and when the Mac wakes up.
- English and Korean UI (follows your system language).

## How it works / privacy

The app opens `claude.ai/settings/usage` in an in-app web view and reads the usage data that page itself loads (falling back to the visible page text). This includes model-specific weekly limits such as Fable.
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

---

## 한국어 안내

Claude의 **5시간 세션 / 주간 사용량**을 메뉴바에서 바로 확인하는 앱이에요. 채팅, Claude Code, Cowork가 같은 한도를 공유해서 퍼센트 하나로 모두 보여요.

### 설치 방법 (macOS 13 이상)

1. [Releases](../../releases)에서 `ClaudeUsageBar.zip`을 받아요.
2. 압축을 풀고 `ClaudeUsageBar.app`을 `응용 프로그램(Applications)` 폴더로 옮겨요.
3. 처음 실행할 때 "확인되지 않은 개발자" 경고가 뜨면(애플 공증을 받지 않은 앱이라서 그래요) 아래 중 하나로 열어요.
   - 앱을 **우클릭 > 열기 > 열기**
   - 또는 터미널에 아래 명령을 붙여넣고 다시 실행해요.

   ```bash
   xattr -dr com.apple.quarantine /Applications/ClaudeUsageBar.app
   ```
4. 메뉴바에 아이콘이 생기면 클릭해서 **로그인**을 눌러요.
   - 구글 로그인은 앱 안에서 막혀 있어요. **이메일로 계속하기**로 로그인하세요. (메일로 온 인증 코드를 입력하면 돼요.)
   - 메일에 링크만 오면 링크를 복사해서 브라우저가 아닌 앱 창 주소로 열어야 해요. 코드 입력이 되는 방식을 권해요.
5. 로그인하면 메뉴바에 `5% · 76%`처럼 (세션 · 주간) 표시돼요. 클릭하면 초기화 시각, 제품별 사용량, 플랜 이름이 보여요.
6. 부팅할 때 자동으로 켜려면 팝오버 아래의 **로그인 시 자동 실행**을 눌러요.

### 안전한가요?

- Claude 토큰이나 키체인을 쓰지 않아요. `claude.ai` 외에는 어디에도 접속하지 않아요.
- 사용량 페이지를 열어 보는 것뿐이라 사용 한도가 줄지 않아요.
- 로그인 정보(쿠키)는 이 앱 안에만 저장돼요.
- 소스가 전부 공개돼 있어요. 비공식 도구이고 Anthropic과 무관해요.

### 자주 겪는 문제

- **메뉴바에 아이콘이 안 보여요**: 메뉴바가 꽉 찼거나 노치 뒤에 가려진 거예요. `⌘`를 누른 채 다른 아이콘을 끌어서 빼 보세요.
- **"로그인"이라고 떠요**: 아이콘 클릭 > 로그인에서 이메일로 다시 로그인하세요.
- **숫자가 안 바뀌어요**: 5분마다 갱신돼요. 아이콘을 클릭하거나 ↻ 버튼을 누르면 4~5초 뒤에 바로 갱신돼요.

---

## License

MIT

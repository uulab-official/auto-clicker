# Auto Clicker

An open-source desktop auto clicker built with Rust and Tauri for macOS,
Windows, and Linux. Configure a simple repeating click or build a sequence of
clicks and delays. Automation runs locally; no account is needed. Update checks
use GitHub Releases.

## 한국어

Auto Clicker는 Rust와 Tauri로 만든 오픈소스 데스크톱 자동 클릭 도구입니다.
단순 반복 클릭과 여러 위치를 순서대로 클릭하는 매크로를 지원합니다. 실행은 앱에서
시작하며 `Ctrl+Shift+F8`은 실행을 정지합니다. 현재 소스에는 macOS의 대체 단축키
`Ctrl+Shift+Escape`도 포함되어 있으며, 키보드 설정에 따라 F8에는 Fn 또는 지구본 키가 필요할 수 있습니다.
공개된 v0.1.4에서 물리 F8 중지 실패가 보고됐으며 원인은 아직 확인되지 않았습니다.
등록에 성공한 단축키는 앱에 표시됩니다. macOS에서는 손쉬운 사용 권한이
필요합니다. Linux에서는 전역 긴급 정지를 보장할 수 없는 Wayland 세션의
클릭 실행을 차단하므로 X11 세션을 사용하세요.
시작 전 0~60초 대기와 단계 복제로 작업을 더 편하게 준비할 수 있습니다.
설정은 JSON 파일로 내보내거나 불러올 수 있습니다. 불러오면 현재 설정이 바뀌므로 필요하면 먼저 백업하세요.
개발 환경과 빌드 방법은 아래 Development 항목을 참고하세요.
`main`에 push하거나 PR을 병합하면 세 플랫폼 검사와 서명된 업데이트 검증을 거쳐 새 패치 릴리스가 자동 공개됩니다. 상세 내용은 아래 Release and updates를 참고하세요.

## 日本語

Auto Clicker は Rust と Tauri で作られたオープンソースのデスクトップ用自動
クリックツールです。単純な繰り返しクリックと、複数の位置を順番にクリックする
マクロに対応します。アプリから開始し、`Ctrl+Shift+F8` で停止できます。現在のソースには macOS 用の
`Ctrl+Shift+Escape` も含まれます。キーボード設定によっては F8 に Fn または地球儀キーを
併用します。登録できたショートカットはアプリに表示されます。
公開済み v0.1.4 では物理 F8 キーによる停止の失敗が報告されており、原因は未確認です。
開始前の待機時間（0〜60秒）とステップの複製にも対応します。
設定を JSON ファイルとして書き出し、読み込めます。読み込みは現在の設定を置き換えます。
macOS ではアクセシビリティの許可が必要です。Linux の Wayland セッションでは
緊急停止を保証できないためクリックを無効にしています。X11 を使用してください。開発とビルドの手順は下記 Development を参照してください。
`main` への push または PR のマージ後、3 プラットフォームの検査と署名済み更新の検証を経て、新しいパッチリリースが自動公開されます。詳細は下記 Release and updates を参照してください。

## Features

- Repeat a click at the current pointer position or a specified position.
- Compose a sequence of clicks and delays and repeat it a fixed number of times
  or until stopped.
- Duplicate a sequence step, and optionally wait up to 60 seconds before the
  first action to give yourself time to switch windows. The wait can be stopped.
- Export settings to a JSON backup or import a backup to replace the current
  settings. Cancelled or invalid imports leave current settings unchanged.
- Start and stop using the application. The global shortcut **Ctrl+Shift+F8**
  stops a running sequence; it does not start one. Current source also offers
  **Ctrl+Shift+Escape** on macOS when successfully registered.
  The app displays the shortcuts that registered successfully. Some Mac
  keyboards require holding Fn or Globe to use F8 as a function key.

Keyboard recording and replay are not currently implemented. Operating-system
input permissions and display-server restrictions apply; see below.

## Platform notes

- **macOS:** Allow the app in System Settings → Privacy & Security →
  Accessibility when prompted. The operating system may require additional
  permissions depending on the input APIs used. Recheck permissions after
  replacing a development build. A physical F8 emergency-stop failure was
  reported with the public v0.1.4 release; its cause remains unconfirmed.
  Test stopping before unattended use and keep the app's Stop button accessible.
- **Windows:** The installers are currently unsigned. Microsoft Defender SmartScreen
  may display an unknown publisher warning, and security policies may block it.
  Applications running with elevated privileges or protected applications may
  not accept synthetic input from a normally launched app.
- **Linux:** The initial input and global-shortcut implementation targets X11.
  Wayland sessions cannot guarantee the emergency stop shortcut, so clicking
  is disabled in those sessions. Sign in to an X11 session to use the app.
  The app must be able to register its stop shortcut before it starts clicking.

Behavior on a particular OS, display server, application, or multi-monitor setup
should be verified on that environment; a successful build alone does not prove
that input injection works there.

## Development

Install a current stable [Rust toolchain](https://rustup.rs/), Node.js 22.18 or
newer, npm, and the [Tauri system prerequisites](https://v2.tauri.app/start/prerequisites/)
for your platform. On macOS install Xcode Command Line Tools; on Windows install
Microsoft C++ Build Tools and WebView2 as described in the Tauri guide.

For Debian/Ubuntu Linux, Tauri's development dependencies can be installed with:

```sh
sudo apt update
sudo apt install build-essential curl wget file libwebkit2gtk-4.1-dev \
  libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev
```

Then install the JavaScript dependencies and start the desktop app:

```sh
npm ci
npm run tauri dev
```

To run the frontend build, Rust tests, and a production desktop build:

```sh
npm run build
npm test
cargo test --manifest-path src-tauri/Cargo.toml
npm run tauri build
```

The production build output is placed under `src-tauri/target/release/`.
Signing and distribution credentials are not included in this repository.

## Release and updates

A push or pull-request merge to `main` starts an automatic public release.
Contributors do not need to create a version tag or publish a draft. The
workflow selects the next unused patch version, including existing tags and
drafts, and commits only the version files to `main`. It tests that exact
release commit on macOS, Windows and Linux, then builds macOS Apple Silicon and
Intel, Linux x86-64, and Windows x86-64 bundles. It verifies updater metadata
and signatures and macOS signing and notarization before publishing the draft.
The GitHub Releases updater then offers the latest published version; installation
still requires the user's choice.

Releases are serialized. If `main` advances before an older run reserves or
publishes its release, that run is skipped or leaves its draft in place; the
newer push is processed separately. Failed builds or validation do not publish
the draft. Existing releases and drafts are not repurposed or overwritten; the
existing v0.1.5 draft is preserved. An interrupted run can resume only its own
verified draft. Inspect the Actions run and remote release state
before retrying a failed or interrupted release. These automated checks do not
replace actual installation and input testing on each supported environment.

A manually pushed `vMAJOR.MINOR.PATCH` tag still runs the separate tag workflow
and produces a verified draft, not an automatically published release. Its tag
and all version files must match. The release workflow can also be run manually
for verification builds without creating a release.

Repository maintainers must configure the GitHub Actions secrets
`TAURI_SIGNING_PRIVATE_KEY` (the full private key contents) and, if the key is
password protected, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`. The matching public
key is embedded in the app configuration. Keep the private key safe and never
commit it. Rotating the updater key requires a migration strategy for already
installed apps. The first update check will fail until a signed release is
published; verify updates from an installed, signed build on each platform.

Updater signatures authenticate updates; they are separate from operating-system
code signing and macOS notarization. Tagged macOS builds require GitHub Actions
secrets `APPLE_CERTIFICATE` (base64 PKCS#12), `APPLE_CERTIFICATE_PASSWORD`,
`APPLE_SIGNING_IDENTITY`, `APPLE_API_KEY`, `APPLE_API_ISSUER`, and
`APPLE_API_KEY_P8` (the PEM contents). Without those secrets, manual builds can
run only as unsigned verification builds. The initial Windows installers are unsigned and may trigger SmartScreen or be
blocked by security policy. A valid updater signature does not establish Windows
publisher identity. macOS release artifacts must be checked for Developer ID
signing and notarization before publication.
Linux's built-in updater applies to AppImage installations; other Linux package
formats need their distribution's update mechanism.

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under the [MIT License](LICENSE).

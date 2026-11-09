# Auto Clicker

An open-source desktop auto clicker built with Rust and Tauri for macOS,
Windows, and Linux. Configure a simple repeating click or build a sequence of
clicks and delays. Automation runs locally; no account is needed. Update checks
use GitHub Releases.

## 한국어

Auto Clicker는 Rust와 Tauri로 만든 오픈소스 데스크톱 자동 클릭 도구입니다.
단순 반복 클릭과 여러 위치를 순서대로 클릭하는 매크로를 지원합니다. 실행은 앱에서
시작하며 `Ctrl+Shift+F8`은 실행을 정지합니다. macOS에서는 손쉬운 사용 권한이
필요하고 Linux는 X11을 우선 지원합니다. Wayland 동작은 보장되지 않습니다.
개발 환경과 빌드 방법은 아래 Development 항목을 참고하세요.

## 日本語

Auto Clicker は Rust と Tauri で作られたオープンソースのデスクトップ用自動
クリックツールです。単純な繰り返しクリックと、複数の位置を順番にクリックする
マクロに対応します。アプリから開始し、`Ctrl+Shift+F8` で停止できます。
macOS ではアクセシビリティの許可が必要です。Linux は X11 を優先し、Wayland
での動作は保証されません。開発とビルドの手順は下記 Development を参照してください。

## Features

- Repeat a click at the current pointer position or a specified position.
- Compose a sequence of clicks and delays and repeat it a fixed number of times
  or until stopped.
- Start and stop using the application. The global shortcut **Ctrl+Shift+F8**
  stops a running sequence; it does not start one.

Keyboard recording and replay are not currently implemented. Operating-system
input permissions and display-server restrictions apply; see below.

## Platform notes

- **macOS:** Allow the app in System Settings → Privacy & Security →
  Accessibility when prompted. The operating system may require additional
  permissions depending on the input APIs used. Recheck permissions after
  replacing a development build.
- **Windows:** Applications running with elevated privileges or protected
  applications may not accept synthetic input from a normally launched app.
- **Linux:** The initial input and global-shortcut implementation targets X11.
  Wayland support is not guaranteed: desktop environments restrict simulated
  input and global shortcuts in different ways. Use an X11 session if needed.
  The app must be able to register its stop shortcut before it starts clicking.

Behavior on a particular OS, display server, application, or multi-monitor setup
should be verified on that environment; a successful build alone does not prove
that input injection works there.

## Development

Install a current stable [Rust toolchain](https://rustup.rs/), Node.js 20 or
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
cargo test --manifest-path src-tauri/Cargo.toml
npm run tauri build
```

The production build output is placed under `src-tauri/target/release/`.
Signing and distribution credentials are not included in this repository.

## Release and updates

The release workflow runs only when a `vMAJOR.MINOR.PATCH` tag is pushed. The
version in the tag, `package.json`, and `src-tauri/tauri.conf.json` must match.
It builds macOS Apple Silicon and Intel, Linux x86-64, and Windows x86-64 bundles,
signs updater artifacts, and assembles `latest.json` on a draft GitHub Release.
The workflow publishes the release only after all builds and metadata checks
succeed. A failed workflow can leave a draft release for investigation.

Repository maintainers must configure the GitHub Actions secrets
`TAURI_SIGNING_PRIVATE_KEY` (the full private key contents) and, if the key is
password protected, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`. The matching public
key is embedded in the app configuration. Keep the private key safe and never
commit it. Rotating the updater key requires a migration strategy for already
installed apps. The first update check will fail until a signed release is
published; verify updates from an installed, signed build on each platform.

Updater signatures authenticate updates; they are separate from operating-system
code signing and macOS notarization. Those credentials and release steps are not
configured by this workflow, so downloads may encounter OS security warnings.

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under the [MIT License](LICENSE).

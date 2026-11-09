# Auto Clicker 0.1.1

This maintenance release updates the version and release pipeline for Auto
Clicker. The clicker features are unchanged. The app checks for updates at
startup; installing an update requires your confirmation.

- **macOS:** The Apple Silicon and Intel builds are signed and notarized. Allow
  Accessibility access to use automated clicks.
- **Windows:** Installers are unsigned and may trigger SmartScreen warnings or
  be blocked by security policy.
- **Linux:** X11 is the initial target; Wayland input and shortcuts are not
  guaranteed. In-app updates apply to AppImage. Update DEB and RPM packages
  using their package manager.

## 한국어

자동 클릭 기능은 그대로이며, 배포 과정을 정비한 유지보수 버전입니다. 새 버전은 앱 시작 시 확인하고 설치는 사용자가 선택합니다.
Windows 설치 파일은 서명되지 않아 보안 경고가 표시될 수 있습니다.

## 日本語

クリック機能はそのままに、配布の仕組みを整えたメンテナンスリリースです。起動時に更新を確認し、インストールは利用者が選択します。
Windows インストーラーは未署名のため、警告が表示される場合があります。

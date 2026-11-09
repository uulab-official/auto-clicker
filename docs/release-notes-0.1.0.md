# Auto Clicker 0.1.0

The first release of an open-source desktop auto clicker for macOS, Windows,
and Linux. Choose a simple repeating click or create a sequence of clicks and
waits. Settings remain on your device. The app checks GitHub Releases for
updates; installing an available update requires your confirmation.

- Click at the current pointer or a captured position, with left, right, or
  middle button and single or double click.
- Reorder click and wait steps and repeat a sequence a set number of times or
  until stopped.
- Stop a running sequence using **Ctrl+Shift+F8**.
- Use the interface in Korean, English, or Japanese.

## Installation and limitations

- **macOS:** Choose the Apple Silicon or Intel build for your Mac. The app needs
  Accessibility permission to control the pointer. The included disk images are signed with Developer ID and notarized by Apple.
  Builds from the manual verification workflow are unsigned.
- **Windows:** These initial installers are **not code signed**. Microsoft
  Defender SmartScreen may show an unknown publisher warning and security
  policies may prevent installation or execution. Some protected or elevated
  applications may not accept simulated clicks.
- **Linux:** X11 is the initial target. Wayland input and global shortcuts vary
  by compositor and are not guaranteed. Automatic updates apply to AppImage;
  update `.deb` and `.rpm` installations through their package mechanism.

Updater packages are cryptographically signed; this is separate from OS code
signing. The update signatures and versions have been checked in CI, but the
complete installed-app update flow has not yet been verified on each platform.
Keyboard recording and replay are not included in this release.

## 한국어

단순 반복 클릭과 여러 위치의 순차 클릭을 지원합니다. 실행은 앱에서 시작하며
`Ctrl+Shift+F8`로 정지합니다. Windows 설치 파일은 서명되지 않아 SmartScreen
경고나 실행 차단이 나타날 수 있습니다. macOS는 손쉬운 사용 권한이 필요하고,
Linux Wayland 지원은 보장되지 않습니다.

## 日本語

単純な繰り返しクリックと複数位置の順次クリックに対応します。アプリから開始し、
`Ctrl+Shift+F8` で停止します。Windows インストーラーは未署名のため、
SmartScreen の警告や実行のブロックが発生する場合があります。macOS では
アクセシビリティの許可が必要です。Linux Wayland の動作は保証されません。

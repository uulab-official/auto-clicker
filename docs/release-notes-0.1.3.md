# Auto Clicker 0.1.3

This release improves click safety, update handling, and accessibility.

- Clicks at a fixed position now stop with an error if the pointer cannot reach the requested location. Starting is disabled when the global emergency stop shortcut is unavailable.
- On Linux, clicking is disabled in Wayland sessions because the global emergency stop cannot be guaranteed. Sign in to an X11 session to use the clicker.
- Update checks handle overlapping requests safely and install only the version you selected. The app checks for updates at startup; installation requires your confirmation.
- Improved settings validation, keyboard focus during status changes, translations, and application icons.
- Windows installers are unsigned and may trigger SmartScreen warnings or be blocked by security policy. On macOS, allow Accessibility access to control the pointer. Linux in-app updates apply to AppImage; update DEB and RPM packages using their package manager.

## 한국어

이번 버전은 클릭 안전성, 업데이트 처리와 접근성을 개선합니다.

- 지정 좌표에 포인터를 놓을 수 없으면 잘못된 위치를 클릭하지 않고 오류와 함께 중지합니다. 전역 긴급 정지 단축키를 사용할 수 없으면 시작이 비활성화됩니다.
- Linux Wayland 세션에서는 전역 긴급 정지를 보장할 수 없어 클릭 실행이 차단됩니다. 클릭 기능은 X11 세션에서 사용해 주세요.
- 동시에 진행된 업데이트 확인을 안전하게 처리하며 선택한 버전만 설치합니다. 업데이트는 시작 시 확인하고 설치는 사용자가 선택합니다.
- 설정 값 검증, 상태 변경 시 키보드 포커스, 번역과 앱 아이콘을 개선했습니다.
- Windows 설치 파일은 서명되지 않아 SmartScreen 경고 또는 보안 정책에 의한 차단이 발생할 수 있습니다. macOS에서는 손쉬운 사용 권한이 필요합니다. Linux 앱 내 업데이트는 AppImage에 적용되며 DEB·RPM은 패키지 관리자를 이용해 업데이트해 주세요.

## 日本語

このリリースでは、クリックの安全性、更新処理、アクセシビリティを改善しました。

- 指定位置にポインターを移動できない場合は誤った位置をクリックせず、エラーで停止します。グローバル緊急停止ショートカットを利用できない場合は開始できません。
- Linux の Wayland セッションではグローバル緊急停止を保証できないため、クリックを実行できません。X11 セッションでご利用ください。
- 重複した更新確認を安全に処理し、選択したバージョンのみをインストールします。更新は起動時に確認し、インストールは利用者が選択します。
- 設定値の検証、状態変更時のキーボードフォーカス、翻訳、アプリアイコンを改善しました。
- Windows インストーラーは未署名のため、SmartScreen の警告やセキュリティポリシーによるブロックが発生する場合があります。macOS ではアクセシビリティの許可が必要です。Linux のアプリ内更新は AppImage に適用されます。DEB・RPM はパッケージマネージャーで更新してください。

# Contributing

Contributions, bug reports, and platform compatibility reports are welcome.
Please include your operating system and version, desktop environment and display
server on Linux, steps to reproduce, and the expected and actual behavior. Do not
include private information in screenshots or logs.

1. Fork the repository and create a branch for your change.
2. Set up the prerequisites in the README and make a focused change.
3. Run the checks in the README and test behavior on the platforms available to you.
4. Open a pull request describing the change, how you tested it, and any platform
   limitations. Report untested platforms explicitly.

Merging the pull request, or pushing directly to `main` with permission, starts
the automatic release process. It assigns a new patch version and publishes only
after the supported platform checks and artifact verification succeed. You do
not need to change version files, create a tag, or publish a release yourself.
If `main` advances during a run, that older run may be skipped or leave a draft
and the newer push is processed separately. Check the Actions log and existing
release state before retrying; report failures rather than overwriting a tag.
Windows installers are currently unsigned, and macOS v0.1.4 has a reported
physical F8 emergency-stop failure whose cause is unconfirmed; see the README.

## 한국어

변경 사항을 PR로 제출하고 사용 가능한 환경에서 테스트해 주세요. PR이 `main`에
병합되거나 권한 있는 개발자가 `main`에 push하면 자동으로 패치 버전을 생성하고,
플랫폼 검사와 산출물 검증을 통과한 뒤 릴리스를 공개합니다. 버전 파일이나 태그를
수동으로 만들 필요는 없습니다. 실행 중 `main`이 앞서가면 이전 실행은 건너뛰거나
초안을 남기고 최신 push를 처리합니다. 실패 시 Actions와 릴리스 상태를 확인하고
기존 태그를 덮어쓰지 마세요. Windows 미서명과 macOS v0.1.4의 미확인 F8 문제는
README의 플랫폼 안내를 참고하세요.

## 日本語

変更は PR で提出し、利用できる環境でテストしてください。PR の `main` への
マージまたは権限のある開発者の `main` への push でパッチバージョンを自動生成し、
プラットフォーム検査と成果物の検証後にリリースを公開します。バージョンファイルや
タグを手動で作る必要はありません。実行中に `main` が進んだ場合、古い実行は
スキップされるか下書きを残し、新しい push を処理します。失敗時は Actions と
リリースの状態を確認し、既存タグを上書きしないでください。Windows の未署名と
macOS v0.1.4 の物理 F8 停止に関する未解決の報告は README を参照してください。

Please retain the license notices of third-party code and assets. Contributions
are submitted under the repository's MIT license.

export type Language = 'en' | 'ko' | 'ja';
const translations: Record<string, [string, string]> = {
  'A little automation, in your control.':['작은 자동화, 내 손안에서.','小さな自動化を、あなたの手に。'], 'OPEN SOURCE':['오픈소스','オープンソース'], 'DESKTOP AUTOMATION':['데스크톱 자동화','デスクトップ自動化'], 'Make every click count.':['클릭을 더 편리하게.','クリックをもっと快適に。'], "Set up a click or build a sequence. Start when you're ready.":['클릭을 설정하거나 순서를 만들어 보세요. 준비되면 시작하세요.','クリックを設定するか、手順を作成しましょう。準備ができたら開始できます。'], 'Running':['실행 중','実行中'], 'Ready':['준비됨','準備完了'], 'Simple click':['단순 클릭','シンプルクリック'], 'Sequence':['순차 실행','シーケンス'], 'Click configuration':['클릭 설정','クリック設定'], 'YOUR SEQUENCE':['순차 작업','シーケンス'], 'Steps':['단계','ステップ'], 'Actions run from top to bottom, then repeat.':['위에서 아래 순서로 실행한 후 반복합니다.','上から順に実行して繰り返します。'], 'STEP':['단계','ステップ'], 'STEPS':['단계','ステップ'], 'Click':['클릭','クリック'], 'Wait':['대기','待機'], 'Your sequence is empty. Add a click or a wait to get started.':['순서가 비어 있습니다. 클릭이나 대기를 추가하세요.','シーケンスが空です。クリックまたは待機を追加してください。'], '+ Add click':['+ 클릭 추가','+ クリックを追加'], '+ Add wait':['+ 대기 추가','+ 待機を追加'], 'SINGLE ACTION':['단일 동작','単一アクション'], 'Click settings':['클릭 설정','クリック設定'], 'Choose how and where to click.':['클릭 방식과 위치를 선택하세요.','クリック方法と位置を選択してください。'], 'Mouse button':['마우스 버튼','マウスボタン'], 'Left':['왼쪽','左'], 'Right':['오른쪽','右'], 'Middle':['가운데','中央'], 'Click type':['클릭 방식','クリックの種類'], 'Single click':['한 번 클릭','シングルクリック'], 'Double click':['더블 클릭','ダブルクリック'], 'Interval':['간격','間隔'], 'Click location':['클릭 위치','クリック位置'], 'Wherever the pointer is when the click happens':['클릭 시 포인터가 있는 위치','クリック時のポインター位置'], 'Pick position':['위치 선택','位置を選択'], 'Use pointer':['현재 포인터 사용','ポインターを使用'], 'X coordinate':['X 좌표','X 座標'], 'Y coordinate':['Y 좌표','Y 座標'], 'Wait duration':['대기 시간','待機時間'], 'Repeat':['반복','繰り返し'], 'Choose when the run should stop.':['실행을 끝낼 시점을 선택하세요.','実行を終了するタイミングを選択してください。'], 'Until stopped':['중지할 때까지','停止するまで'], 'times':['회','回'], 'Number of repetitions':['반복 횟수','繰り返し回数'], 'RUN CONTROL':['실행 제어','実行コントロール'], 'In progress':['실행 중','実行中'], 'Ready when you are':['시작할 준비가 되었습니다','準備ができました'], 'Review your settings, then start clicking.':['설정을 확인한 뒤 클릭을 시작하세요.','設定を確認してクリックを開始してください。'], 'Stop clicking':['클릭 중지','クリックを停止'], 'Start clicking':['클릭 시작','クリックを開始'], 'Global emergency stop':['전역 긴급 중지','グローバル緊急停止'], 'You can stop a run at any time with the shortcut. Check system permissions if clicking is unavailable.':['단축키로 언제든 실행을 중지할 수 있습니다. 클릭이 안 되면 시스템 권한을 확인하세요.','ショートカットでいつでも停止できます。クリックできない場合はシステムの権限を確認してください。'], 'App updates':['앱 업데이트','アプリのアップデート'], 'Checking for updates…':['업데이트 확인 중…','アップデートを確認中…'], 'Installing update…':['업데이트 설치 중…','アップデートをインストール中…'], 'You have the latest version.':['최신 버전입니다.','最新バージョンです。'], 'Update installed. Restart the app to use it.':['업데이트가 설치되었습니다. 앱을 다시 시작하세요.','アップデートがインストールされました。アプリを再起動してください。'], 'Updates are checked on startup. Installation requires your choice.':['시작할 때 업데이트를 확인하며 설치는 직접 선택합니다.','起動時に更新を確認し、インストールは手動で行います。'], 'Install update':['업데이트 설치','アップデートをインストール'], 'Check for updates':['업데이트 확인','アップデートを確認'], 'Built for the way you work.':['작업 방식에 맞춘 도구.','あなたの作業に合わせたツール。'], 'Settings stay on this device.':['설정은 이 기기에만 저장됩니다.','設定はこのデバイスに保存されます。'], 'Settings could not be saved on this device.':['이 기기에 설정을 저장하지 못했습니다.','このデバイスに設定を保存できませんでした。'], 'Add at least one step before starting.':['시작하기 전에 단계를 하나 이상 추가하세요.','開始する前にステップを追加してください。'], 'Language':['언어','言語']
};
export function translate(text: string, language: Language): string {
  if (language === 'en') return text;
  const slot = language === 'ko' ? 0 : 1;
  if (translations[text]) return translations[text][slot];
  const patterns: [RegExp, (parts: RegExpMatchArray) => [string, string]][] = [
    [/^Fixed position · (-?\d+), (-?\d+)$/, m => [`고정 위치 · ${m[1]}, ${m[2]}`, `固定位置 · ${m[1]}, ${m[2]}`]],
    [/^Completed cycles: (\d+)$/, m => [`완료된 반복: ${m[1]}회`, `完了した回数: ${m[1]}`]],
    [/^Version (.+) is available\.$/, m => [`버전 ${m[1]}을 사용할 수 있습니다.`, `バージョン ${m[1]}を利用できます。`]],
    [/^Move your pointer to the target position\. Capturing in (\d+)…$/, m => [`포인터를 원하는 위치로 이동하세요. ${m[1]}초 후 기록합니다…`, `ポインターを目的の位置に移動してください。${m[1]}秒後に取得します…`]],
    [/^Position captured: (-?\d+), (-?\d+)\.$/, m => [`위치를 기록했습니다: ${m[1]}, ${m[2]}.`, `位置を取得しました: ${m[1]}, ${m[2]}。`]],
    [/^Move step (\d+) up$/, m => [`${m[1]}단계 위로 이동`, `ステップ${m[1]}を上へ`]],
    [/^Move step (\d+) down$/, m => [`${m[1]}단계 아래로 이동`, `ステップ${m[1]}を下へ`]],
    [/^Remove step (\d+)$/, m => [`${m[1]}단계 삭제`, `ステップ${m[1]}を削除`]],
    [/^(\d+) STEPS?$/, m => [`${m[1]}단계`, `${m[1]}ステップ`]],
  ];
  for (const [pattern, replace] of patterns) { const match = text.match(pattern); if (match) return replace(match)[slot]; }
  return text;
}
export function translateDom(root: HTMLElement, language: Language) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const nodes: Text[] = [];
  while (walker.nextNode()) nodes.push(walker.currentNode as Text);
  for (const node of nodes) { const value = node.data.trim(); if (value) node.data = node.data.replace(value, translate(value, language)); }
  root.querySelectorAll<HTMLElement>('[aria-label]').forEach(el => { const value = el.getAttribute('aria-label'); if (value) el.setAttribute('aria-label', translate(value, language)); });
}

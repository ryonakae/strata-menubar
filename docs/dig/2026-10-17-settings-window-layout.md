# dig log: 設定画面のレイアウト改善

## 目的・前提・制約
- Sparkle の dig（`2026-10-17-sparkle-updates.md`）の途中で追加された要望。同じ実装の流れで扱う。
- 要望1: Models のプルダウンとモデル一覧（pack の行）の並び順を揃える。
- 要望2: 設定ウインドウの幅を変えられるようにする。
- 要望3: 設定画面下部の Apply やサーバー操作のボタンを、スクロール中も常に表示する。
- 確認済みの事実（コード）:
  - プルダウン（`SettingsView.modelsSection` の Picker）は、インストール済みモデルを tag のアルファベット順（`StrataInstallation.installedModels()` の `.sorted { $0.tag < $1.tag }`）に並べ、その後ろにダウンロード済み（未準備）の pack を、最後に選択中の未インストールのモデルを並べる。インストール済みには catalog にない独自の `strata-*.json` も含まれうる。
  - pack の行は `StrataModelCatalog.packs` の順（Q2_0, IQ3_XXS, IQ3_S, UD-Q4_K_XL, UD-Q5_K_XL, UD-Q6_K_XL）。たとえば IQ3_S と Q2_0 がインストール済みだと、プルダウンは IQ3_S → Q2_0、一覧は Q2_0 → IQ3_S になる。
  - ウインドウは SwiftUI の `Settings` scene で、`Form` に `.frame(width: 560)` を指定して幅を固定している。
  - 下部の `applySection` には検証メッセージ、Revert、Apply and Restart Server（サーバー起動中のみ）、Apply、説明文がある。その上の `runningSection` にも「Stop and Apply Saved Settings」ボタンがある。

- 実機確認でのフィードバック（2026-10-18、実装 540d8ff / 1bc460b を Debug 版で確認）:
  - ウインドウの大きさが変えられず、端にカーソルを当ててもリサイズ用のカーソルにならない（Q9 を満たしていない不具合として修正する。`Settings` scene の NSWindow は標準ではリサイズ可能になっておらず、`.windowResizability(.contentMinSize)` だけでは足りない）。
  - 固定バーの上に並ぶ検証メッセージが邪魔。もっと適切な場所に出したい（Q10 の見直し）。
  - Strata directory を、ボタンから Finder で場所を選ぶ形にしたい。
  - Server / Engine / Running server のセクションの並びが不自然。
  - Running server セクションの最後に Version の行がついて見えるのが変。About セクションを新設し、バージョン、作者名、GitHub へのリンクなどを置きたい。
- 確認済みの事実（コード）:
  - 検証メッセージ（`StrataSettings.validate` が返す `SettingsIssue`）は、どの設定項目のものかを持っていない。エラーは Strata directory、モデル、コンテキスト、ポート、アイドルアンロード、エキスパートキャッシュ、macOS 用の空きメモリ、verify window、prompt chunk について出る。警告はコンテキスト、メモリ、verify window、MTP、prompt chunk について出る。
  - MTP がないという注意は、Engine セクションの中（オレンジの footnote）と検証メッセージの一覧の両方に出ていて、重複している。
  - 今のセクションの順番: Strata installation → Models → Memory and context → Server → Engine → Running server → （footnote だけのセクション）→ （Version の行だけの、見出しのないセクション）。

## 決定事項
- プルダウンと一覧の両方を `StrataModelCatalog.packs` の順に揃える。プルダウンではインストール済みとダウンロード済み（未準備）の pack を catalog の位置で混ぜて並べ、catalog にない独自の `strata-*.json` はその後ろに tag 順、選択中の未インストールのモデルは最後に置く。一覧は今のまま catalog 順。
  - 理由: catalog 順は「速い・小さい → 高品質・大きい」で選ぶときの軸と一致し、pack の状態が変わっても位置が動かない。
  - 出典: Q8
- 設定ウインドウは幅も高さも変えられるようにする。最小は幅 560pt（今の幅）、高さ 480pt 前後。最大は設けない。初めて開いたときの大きさは今と同じ。
  - 理由: 幅を広げれば長い説明やモデルの行が読みやすく、高さを変えられれば大きい画面でスクロールせずに見られる。560pt は今のレイアウトが崩れないことを確認済みの幅。
  - 出典: Q9
- 下部に常時表示するバーを置き、検証メッセージ（エラーと警告）と Revert / Apply and Restart Server / Apply の3つのボタンを入れる。説明文（"Applied settings are used at the next start..."）と「Running server」セクションの「Stop and Apply Saved Settings」は今の場所に残す。
  - 理由: Apply が押せない理由がボタンの隣に見える。メッセージは通常0〜2件。「Stop and Apply Saved Settings」が出る状態では Apply and Restart Server も押せるので、バーに入れると同じ操作が並ぶ。
  - 出典: Q10
  - 状態: 検証メッセージの置き場所は Q11 で置き換え（撤回・置換済みを参照）。ボタンをバーに置くことは維持する。
- 検証メッセージは、原因になった項目のセクションの中に出す。`SettingsIssue` にどのセクションのものかを持たせ、各セクションが自分の分を表示する。下部のバーにはエラーがあるときだけ件数と「直すと Apply できる」旨の1行を出し、警告はバーに出さない。セクション内にすでにある同じ内容の注意（MTP）と重複させない。
  - 理由: 直す項目のすぐ近くに理由が見え、バーは常に1行以下で済む。振り分けは検証ロジックのテストで確認できる。
  - 出典: Q11（Q10 のうち「検証メッセージをバーに入れる」を置き換え。ボタンをバーに置くことは維持）
- Strata directory はテキストフィールドをやめ、パスを読み取り専用で表示し、「Choose…」ボタンで Finder のフォルダ選択ダイアログから選ぶ。選んだパスは下書きになり、Apply まで保存しない（今の下書きの扱いと同じ）。「Show in Finder」は付けない。
  - 理由: 要望どおり Finder で選ぶ形にし、打ち間違いや空のまま Apply するエラーをなくす。
  - 出典: Q12
- セクションの順番は Running server → Strata installation → Models → Memory and context → Engine → Server → （footnote）→ About とする。
  - 理由: 開いたときにいまの状態（どの設定で動いているか、Stop and Apply の案内）が最初に見える。そのあと「何を動かすか → どう動かすか → どう公開するか」の順になる。
  - 出典: Q13
- 見出し「About」のセクションを新設し、Version 0.2.0 と「Check for Updates…」ボタン、「Made by Ryo Nakae」（リンクなし）、GitHub のリポジトリ（https://github.com/ryonakae/strata-menubar）へのリンク、「MIT License」を載せる。Credits（Font Awesome、Sparkle）は載せない（README に残す）。メニューの「Check for Updates…」はそのまま。
  - 出典: Q14（推奨は Credits も載せる B だったが、ユーザーは A を選択）

## 撤回・置換済み
- Q10 の「検証メッセージ（エラーと警告）を下部のバーに入れる」は、実機で邪魔だったため Q11 の「各セクションに出し、バーはエラーの1行だけ」に置き換えた。

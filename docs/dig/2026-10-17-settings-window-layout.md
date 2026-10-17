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

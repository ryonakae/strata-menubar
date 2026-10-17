# dig log: Sparkle による StrataMenubar のアップデート機能

## 目的・前提・制約
- メニューと設定画面から更新を確認し、そのまま更新・再起動できるようにする。
- 配布は v0.1.1 から `.github/workflows/release.yml` が担う: Developer ID 署名 + Hardened Runtime + 公証済みの `StrataMenubar_<version>_arm64.dmg` と `.sha256` を下書き Release に添付し、公開すると `update-homebrew-cask.yml` が `ryonakae/homebrew-tap` の `Casks/strata-menubar.rb` を更新する。署名用 secret は `release` environment（`v*` タグのみ）。
- 既存の終了処理: `AppDelegate.applicationShouldTerminate` が未適用の設定、アプリが起動したサーバーと setup の停止を確認してから終了する（`terminateLater` で非同期に停止）。
- AGENTS.md の制約: 依存なし（現状）、アプリが起動していないプロセスにはシグナルを送らない、自動再起動ループなし。Invariants の「Strata 自体をインストール・更新しない」は Strata についてで、このアプリ自身の更新は対象外。
- 確認済みの事実: Sparkle の最新は 2.10.0（2026-09-13）。v0.1.0 と v0.1.1 には更新機能がないので、これらの利用者は一度だけ手動で更新する。

## 決定事項
- 更新の仕組みは Sparkle 2 を使う。
  - 理由: Sheltie（Tauri updater）と同じ構成（更新情報ファイル + 専用鍵の署名 + Release への添付）を macOS ネイティブで実現できる。
  - 出典: dig 開始前の会話（ユーザーが「Sparkle にしよう」と回答）
- 入口はメニューと設定画面の両方。
  - 出典: dig 開始前のユーザーの要望
- アプリアイコンと設定画面のバージョン表示は dig とは別に実装済み（未 push のコミット 0d69748, 7af3703）。設定画面の最下部に `aboutSection`（Version x.y.z (build)）がある。
- 更新の確認は手動だけ。メニューと設定画面の「Check for Updates…」を押したときにだけ確認し、自動確認・自動ダウンロードはしない（Sheltie と同じ）。
  - 出典: Q1（推奨は B の自動確認だったが、ユーザーは A を選択）
- 「Install and Relaunch」は既存の終了処理（`AppDelegate.applicationShouldTerminate`）をそのまま通す。アプリが起動したサーバーや setup があれば「Stop and Quit」の確認を出し、同意すれば止めてから更新・再起動する。キャンセルや停止失敗のときは今回は更新せず、Sparkle の標準動作に任せて次の終了時に入れる。更新後にサーバーを自動で起動し直すことはしない。
  - 理由: 終了処理を1か所に保ち、「自分が起動したものだけ止める」「止められなければ終了しない」「明示的な操作なしに起動しない」を守る。
  - 出典: Q2
- 更新ファイルは公証済みの `StrataMenubar_<version>_arm64.dmg` をそのまま使う。CI で EdDSA 署名して `appcast.xml` を生成し、各 Release に添付する。アプリの feed URL は `https://github.com/ryonakae/strata-menubar/releases/latest/download/appcast.xml`。
  - 理由: 1つの DMG を手動ダウンロード・Homebrew・Sparkle で共用できる。`releases/latest` は公開済みの最新だけを指すので、下書きの間は配られず、公開と同時に配られる（tap の更新と同じタイミング）。
  - 出典: Q3
- Sparkle は Swift Package Manager で 2.10.0 に固定して追加し、`Package.resolved` もコミットする。AGENTS.md と README の「依存なし」は「依存は Sparkle だけ。ほかを足すには計画が必要」に書き換える。
  - 理由: Xcode 標準の方法で、ビルドコマンドは変わらず、手元のビルドでも更新機能を確認できる。
  - 出典: Q4
- EdDSA 鍵は手元で Sparkle の `generate_keys` で作る（秘密鍵はログインキーチェーン）。`generate_keys -x` で書き出したものを release environment の secret `SPARKLE_ED_PRIVATE_KEY` に登録し、パスワードマネージャーにもバックアップを残す。書き出したファイルは登録後に削除する。公開鍵は Info.plist の `SUPublicEDKey` に入れる。
  - 理由: GitHub の secret は読み出せずバックアップにならない。キーチェーンだけだと Mac の故障で失う。失うと配布済みの版が更新を検証できなくなる。
  - 出典: Q5
- Homebrew Cask には `auto_updates true` を付けない。`brew upgrade` でもアプリ内の更新でも上げられるようにする。Sparkle で更新したあとの `brew upgrade` が同じ版を入れ直すことは許容する。
  - 理由: 確認は手動だけなので Homebrew 経由の経路も残したい。Sheltie の Cask と揃う。
  - 出典: Q6
- リリースノートは appcast に埋め込まず、`sparkle:fullReleaseNotesLink` で GitHub の Release ページ（`https://github.com/ryonakae/strata-menubar/releases/tag/v<version>`）を指す。appcast は今までどおり下書きの段階で CI が DMG と一緒に作る。
  - 理由: 公開後に appcast を作り直す仕組みが要らず、公開前に GitHub で書いたノートがそのまま見える。
  - 出典: Q7
- メニューの「Check for Updates…」は「Settings…」の直前に置く。設定画面は最下部の Version の行に「Check for Updates…」ボタンを並べる。確認中・更新中の表示は Sparkle の標準ダイアログに任せる。
  - 出典: 終了確認で既定案に合意
- 次の版は v0.2.0。未 push のアイコンとバージョン表示のコミットも含める。Release ノートで、v0.1.x の利用者は一度だけ手動更新が必要と書く。
  - 出典: 終了確認で既定案に合意

## 対象外
- 自動確認（定期チェック）と自動ダウンロード（Q1）
- 更新を入れるためにサーバーや setup を確認なしで止めること、更新後のサーバーの自動起動（Q2）

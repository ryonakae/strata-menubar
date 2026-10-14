# Strata Menubar Implementation Plan

## Requirements

自分のMacで導入済みのStrata（Qwen3.8-Flash-Next Q2_0）を起動・停止し、メモリ関連の設定を変更できる、小さなmacOSメニューバーアプリを作る。ターミナルの専用ペインを不要にし、起動後は既存のPiから利用できる状態にする。

- Swift / SwiftUIによるネイティブアプリ。メニューバー常駐、Dockへの常時表示は不要。
- 起動・停止、状態表示、チャットを開く、ログを開く、設定、アプリ終了を提供する。
- 状態は停止中・起動中・稼働中・停止中処理・エラーを区別する。外部で起動されたStrataも識別して表示する。
- 設定の初期値はStrataの場所 `~/Dev/local/Strata`、expertキャッシュ5 GB、コンテキスト8,192、ポート8080。モデルはQ2_0専用で、画像入力とMTPドラフトは現状の無効設定を維持する。
- 設定は保存し、次回起動に反映する。稼働中に変更した場合は、保存のみと「停止して反映」を選べる。自動では再起動しない。稼働中の実設定と未反映の設定を区別する。
- キャッシュ値はStrata全体のメモリ上限ではないこと、固定指定では自動縮小されないことを設定画面に記す。「全体16 GB前後」は運用目標であり、アプリが保証する上限ではない。
- 接続は `127.0.0.1` のみに限定。アプリが管理するサーバーは子プロセスとして起動し、停止時はエンジンも終了させる。別で起動されたプロセスは勝手に停止しない。
- 稼働中または起動中のアプリ終了では、管理中サーバーも停止することを確認し、停止完了まで終了を保留する。キャンセルできること。
- 対象外：Strataのインストール・更新・モデル取得、他モデル対応、Pi設定の自動編集、ログイン時自動起動、launchdサービス、認証・LAN公開、詳細な性能監視、配布用署名・公証・自動更新。

## Investigation / Handoff

### リポジトリと実機

- 作業場所：`/Users/ryo.nakae/Dev/private/strata-menubar`。調査時点の追跡ファイルは `README.md` と `LICENSE` のみ。既存実装・ビルド・テスト基盤・今回のdig logはない。計画以外は変更していない。
- 実機：Apple M6、32 GiB、macOS 27.0.1。Xcodeはインストール済み。
- Strata本体：`/Users/ryo.nakae/Dev/local/Strata`。確認したコミットは `296b59d2f73c8f04a805df29c2fa97655adace78`。データは兄弟ディレクトリ `Strata-data`。このリポジトリにはモデルやStrata本体をコピーしない。
- 直近の手動起動は `env STRATA_METAL_ARENA_GB=5 ./run-q2_0.sh`。キャッシュ充填後のエンジンfootprintは約10.6 GB、短い応答で約13〜15 tok/s。長文入力中の全体ピークは未検証。
- 会話中のバックグラウンド切り替え作業では、Herdrペイン `w1:p11` のサーバーを正常停止したところまで実施済み。nohupでの再起動は未実施。実装開始時に現在の状態を再確認すること。ペインIDを製品コードに埋め込まない。
- Pi接続は `http://127.0.0.1:8080/v1`、モデル名 `qwen3.8-flash-next-q2_0`。`~/Dev/local/.pi/models.json` はcontextWindow 8192 / maxTokens 2048。ポート・コンテキスト変更時はPi側も手動調整が必要だと案内し、勝手に書き換えない。

### 確認済みのStrata契約

参照：[Mac版](https://github.com/Niko1221/Strata/blob/296b59d2f73c8f04a805df29c2fa97655adace78/docs/MAC.md)、[server.py](https://github.com/Niko1221/Strata/blob/296b59d2f73c8f04a805df29c2fa97655adace78/serve/server.py)、[arena_budget.h](https://github.com/Niko1221/Strata/blob/296b59d2f73c8f04a805df29c2fa97655adace78/metal/src/engine/arena_budget.h)。実装時は導入済みコードとの一致を確認する。

- Python：`<Strata>/.venv/bin/python`、サーバー：`<Strata>/serve/server.py`、ベース設定：`<Strata>/strata-q2_0.json`。
- 起動引数：`--engine strata --config <実行用JSON> --host 127.0.0.1 --port <設定値>`。作業ディレクトリはStrata本体。`--open`を付けず、ブラウザはメニューから開く。`run-q2_0.sh`は`--open`付きなので直接使わない。
- 設定JSONは `exe`、`args`、`cwd`、`tokenizer`、`model_name`、`log`、`backend`、`env`などを持つ。`args`の `--max-context` を更新する。現在の `--spec 2` だけではMTP有効とは判断できず、実際にはドラフトの指定がなくMTPなしで動作している。無関係な引数を変更しない。
- JSONの `env` はエンジン起動環境へ反映される。固定キャッシュは `STRATA_METAL_ARENA_GB`（単位は10進GB）。`STRATA_METAL_STREAM=1`を維持する。
- `/health` の確認済みレスポンス：`status: "ok"`、`service: "strata"`、`loaded: true`、`model: "qwen3.8-flash-next-q2_0"`、`max_context: 8192`。HTTP 200だけで稼働中にしない。
- `serve/server.py` の稼働後のSIGTERM処理はKeyboardInterrupt経由で正常終了へ進み、エンジンの `close()` はQUIT、期限付き待機、terminate / killへ進む。停止は即時とは限らない。
- **SIGTERMハンドラは起動完了後に登録される。起動途中にPythonのPIDへSIGTERMを送るだけでは、エンジンが残る危険がある。** 起動途中の停止・異常終了も所有プロセスの終了確認が必要。
- `STRATA_METAL_KEEP_FREE_GB` は全体の使用量制限ではない。24 / 16 GB指定で利用可能メモリが不足し、arenaが約0.8 GBまで縮んで `metal prompt: no arena region for the prompt buffers` が発生した。5 GB固定では入力処理用1.36 GBの領域をarena内に確保して成功した。自動調整への置換は今回行わない。

## Implementation Decisions

### アプリ構成と設定

- macOS 15以上を対象にSwiftUI `MenuBarExtra`と設定画面を使用。必要な終了確認・アプリライフサイクルはAppKitで補う。依存ライブラリは追加しない。
- `StrataMenubar.xcodeproj` にアプリと単体テストのターゲット、および共有scheme `StrataMenubar` を用意する。ローカル実行可能な `.app` を成果物にする。
- 外部の既存Python・Metalエンジンを実行する用途なので、App Sandboxで囲う設計にはしない。管理者権限、アクセシビリティ権限、Full Disk Access、システムのセキュリティ緩和は要求しない。
- ユーザー設定はアプリのUserDefaults、実行用JSONはアプリ専用Application Support、ログはアプリ専用Library/Logsへ保存する。リポジトリやバンドルにマシン固有の実設定を含めない。
- 起動ごとに最新のベースJSONを読み、管理項目だけを変更した実行用コピーを作る。元の `strata-q2_0.json`、起動スクリプト、モデルは編集しない。生成JSONのログ先もアプリ管理下へ向け、stdout/stderrのサーバーログとエンジンログを区別して開けるようにする。
- 引数は配列として組み立て、シェル文字列連結や `eval` は使わない。空白・日本語を含むパスを扱う。実行に必要なPython・サーバー・ベース設定・モデル参照先を事前確認し、不足や非対応設定は具体的に表示する。
- 入力値は正の有限キャッシュ値・正の整数コンテキスト・有効な非特権ポートとして検証する。小さすぎるキャッシュでの実績を踏まえた注意、大きいコンテキストやキャッシュの負荷を表示するが、未検証の値を安全と保証しない。境界値の具体的なUI設計は実装時に確定する。

### プロセス所有と状態

- 起動・停止・再起動操作を一つの管理コンポーネントで直列化する。連打で複数プロセスを起動しない。古いhealth応答や終了通知が新しい起動の状態を上書きしないよう起動単位を識別する。
- 管理プロセスを独立したプロセスグループで起動し、直接の子PIDと所有グループを保持する。Swiftからの `posix_spawn` / `POSIX_SPAWN_SETPGROUP` 等、OS標準機能を用いた最小の実装でよい。PIDファイルだけで所有権を復元したり、プロセス名の一括killをしたりしない。
- 正常稼働後はまずサーバーへSIGTERMを送り、上流のエンジン終了処理を待つ。起動途中の停止、親の異常終了、停止タイムアウトは別経路として扱い、所有グループ内だけを後始末する。上流の終了待機時間を考慮し、即座の強制終了はしない。停止できなければエラーを表示し、停止成功や再起動可能とは扱わない。
- ログはファイルへ直接出力するなど、未読pipeによるプロセス停止とUIメモリへの無制限蓄積を避ける。最低限、過去ログの肥大化を抑える保持方針を設ける。
- 起動前に既存の `/health` とポート利用を確認。外部Strataは閲覧用状態とし、起動・停止・「停止して反映」の対象にしない。別サービスや応答不明のポート占有は競合として表示する。事前確認後の競合もサーバーの起動失敗として処理する。
- health確認はUIをブロックせず、要求ごとのタイムアウトと起動待ち期限を設ける。起動待ち期限を超えても生存する所有プロセスを放置して再起動しない。稼働後のhealth不調とプロセス終了は区別し、自動再起動ループは実装しない。
- アプリ異常終了後の孤児や手動起動サーバーを、再起動したアプリが勝手に引き取って停止しない。外部稼働として案内する。通常の停止・アプリ終了経路で子孫が残らないことを保証対象にする。

## Tasks

Review base commit: `fe85445`（Initial commit）。

- [x] **ビルド可能なメニューバーアプリの土台**：`StrataMenubar.xcodeproj`、`StrataMenubar/App/` を作成し、MenuBarExtra・設定ウィンドウ・終了フロー・共有schemeを用意する。
  - 実装：`PBXFileSystemSynchronizedRootGroup` でフォルダ同期するプロジェクト（objectVersion 77）、`LSUIElement` はビルド設定で生成。終了フローは `QuitRequirement(state:ownsProcess:)` で判定し、`AppDelegate` が確認・保留・キャンセルを扱う。テストはSwift Testing。
  - 検証：Final Validationのbuild/testコマンドで成功（QuitRequirementTests 4件）。Swiftマクロのplugin serverは内側で `sandbox-exec` を使うため、エージェントのSafehouseサンドボックス内では `malformed response` で失敗する。ビルド・テストはHerdrペイン（サンドボックス外）に委譲して実行した。
- [x] **設定と実行用JSON生成**：`StrataMenubar/Settings/` と `StrataMenubar/Strata/` に設定保存、入力検証、Strata導入状況の確認、ベースJSONからのコピー生成を実装する。`StrataMenubarTests/` に元データ保全・引数更新・パス処理のテストを追加する。
  - 実装：`StrataSettings.validate()` はエラー（非正・非有限キャッシュ、非正コンテキスト、1024〜65535外のポート、空ディレクトリ）と警告（キャッシュ3 GB未満・12 GB超、コンテキスト8192超・2048未満）を返す。`RunConfig.make` は `args` の `--max-context`、`env` の `STRATA_METAL_ARENA_GB`（`STRATA_METAL_STREAM` が無ければ `1` を補う）、`log`、`port` だけを変更し、他のキーは保持する。`StrataInstallation.check` はPython・server.py・ベースJSON・`exe`・`--pack/--native/--ple-gguf/--expert-profile` の参照先・tokenizer・`model_name == qwen3.8-flash-next-q2_0` を確認する。実行用JSONは `~/Library/Application Support/StrataMenubar/strata-q2_0.run.json`、ログは `~/Library/Logs/StrataMenubar/{server,engine}.log`（10 MB超で `.1` へ退避）。
  - 検証：testコマンドで22件成功（設定の保存・検証、無関係キーの保持、コンテキスト引数の更新・追加、空白と日本語を含むパス、元JSONのバイト一致、Python欠落・別モデルの具体的なエラー）。
- [x] **サーバーのライフサイクル管理**：`StrataMenubar/Strata/` に所有プロセスの起動・停止、非同期health確認、外部稼働・競合検出、エラーとログの処理を実装する。実モデルを起動せず検証できる状態テストと、子プロセスを作る小さなテスト用fixtureで所有範囲・停止を検証する。
  - 実装：`PosixProcessLauncher` は `posix_spawn` + `POSIX_SPAWN_SETPGROUP`（新しいプロセスグループ）、stdinは `/dev/null`、stdout/stderrは `server.log` へ追記、`CLOEXEC_DEFAULT` でfdを継承しない。終了は `DispatchSource` のprocess exitで `waitpid` し、所有グループの生存は `kill(-pgid, 0)` で判定する。`ServerManager` は start/stop/restart/予期せぬ終了/起動期限超過を1本の直列キューで処理し、起動ごとのgenerationで古いhealth応答・終了通知を無視する。稼働中の停止はサーバーPIDへSIGTERM→最大90秒待機→残るグループにSIGTERM（20秒）→SIGKILL（10秒）。起動途中の停止・異常終了・期限超過はグループにだけシグナルを送る。停止失敗時は `failed` のまま所有を保持し、再起動を抑止する。稼働後のhealth不調は `RunningInfo.health` に表示するだけで再起動しない。
  - 検証：testコマンドで49件成功。fake launcher/probeによる状態テスト（連打で1プロセス、loaded前は起動中、遅延health応答が次の起動を汚さない、外部Strataにシグナルを送らない、競合・導入不備・spawn失敗、起動途中の終了、期限超過、SIGTERM→グループTERM→KILLの順序、停止失敗時の所有保持、設定反映再起動、health不調の表示、停止完了待ち）と、`/bin/sh` fixture（孫 `sleep` を持つ）での実プロセステスト（独立グループ、グループ信号で子孫が消える、TERM無視→KILL、引数・cwd・ログ転送、無関係プロセスに影響しない、起動途中の停止）。
  - 修正記録：`waitForIdle()` が完了済みTaskの `value` を待つだけで `operation = nil` の継続が走らずビジーループした（`sample` で確認）。`enqueue` がTask内部で自分をクリアする形に変更。`withTaskGroup` によるタイムアウト競争は、終了しないプロセスの待ちを抱えて戻れないため、`exitIfFinished()` のポーリングに置換。
- [ ] **メニューと設定の接続**：`StrataMenubar/Views/` とApp層に状態別表示・操作可否・設定の未反映表示・「停止して反映」・チャットとログを開く操作を実装する。現在動くサーバーのURLは未反映設定ではなく、実際の起動設定から作る。
- [ ] **実機検証と利用手順**：`README.md` にビルド、アプリ起動、Strataの事前導入、設定変更、停止、ログ確認、ポート／コンテキスト変更時のPi側調整を記載する。以下の検証を実施し、結果と残る制約をこの計画へ記録する。

## Final Validation

新規に作成するschemeを次のコマンドで検証できるようにする。現時点ではプロジェクト未作成であり、これらは未実行。

- [ ] `xcodebuild -project StrataMenubar.xcodeproj -scheme StrataMenubar -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build` → アカウント設定なしでローカル `.app` をビルドできる。
- [ ] 同じ指定の末尾を `test` として単体テストを実行 → 設定の保存・検証、元JSONを変更しないコピー生成、無関係なキーの保持、コンテキスト引数の更新、ローカル限定接続、空白を含むパスが正しい。
- [ ] 自動ライフサイクルテスト → 起動連打は1プロセス、loaded前は起動中、遅延healthが次の起動を汚さない、外部サービスへシグナルを送らない、起動失敗・異常終了・タイムアウトを停止成功と誤認しない。
- [ ] テスト用親子プロセスで稼働後停止・起動途中停止・設定反映再起動・終了キャンセル・アプリ正常終了を検証 → 所有する子孫が残らず、無関係なプロセスには影響しない。停止が失敗するfixtureでは再起動を抑止し、エラー表示する。
- [ ] 実機でアプリを起動 → Dockに常時表示せずメニューバーと設定画面を操作でき、起動・停止待ち中もUIが応答する。GUI操作には適用される `cua-driver` 等のスキルに従う。画面検証を実施できなければ未検証と明記し、ユーザー確認へ引き継ぐ。
- [ ] 実Strataを5 GB / 8K / 8080で一度起動 → `/health` のmodel・loaded・max_contextを確認し、ブラウザで短い質問が応答する。変更前後のメモリプレッシャー・スワップとエンジンログを記録する。過去のスワップ累計を今回の増加と誤認しない。
- [ ] 設定保存のみでは稼働プロセスが変化せず、「停止して反映」で正常停止後に新しい値で1プロセスだけ起動する。代表的な設定変更を実測し、元JSONとモデルデータに変更がないことを確認する。
- [ ] Piから既存のStrataモデルへ短い質問を送り応答を確認する。Piのグローバル設定やデフォルトは変更しない。既存8Kコンテキストで通常の全ツール構成まで保証したとは報告しない。
- [ ] 実サーバー停止と稼働中のアプリ終了 → サーバー・Metalエンジンが終了し、ポートが解放される。ログだけでなくプロセスの終了も確認する。
- [ ] `git diff --check`、差分とREADMEのコマンド・参照パスを確認 → モデル・実行ログ・生成設定・ビルド成果物・秘密が追跡対象に混入せず、合意範囲外の変更がない。

実機適用・GUI検証は通常のユーザー環境で行う。エージェントのsandboxで操作が拒否された場合、権限を緩和せず必要な操作をユーザーへ引き継ぐ。実モデルの再ダウンロードや検証目的のシステム設定変更は行わない。

> 各タスクは対応する検証が成功してから完了にする。実装中の軽微な差分と検証結果は該当箇所へ反映し、要件、対象外、公開契約の変更はユーザーへ確認する。最終確認では有効な検証結果を再利用し、計画と実際の変更が一致することを確認する。必要な検証と実装側の必須レビューが通ったら、計画を同名のまま `docs/plans/archived/` へ移す。

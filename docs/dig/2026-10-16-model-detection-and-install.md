# dig log: モデルの自動検出／更新と、アプリ内でのモデルのダウンロード（進捗表示）・削除

## 目的・前提・制約
- 目的（ユーザーの発言、2026-10-16）:
  1. setup で新しいモデルを導入したあと、アプリを再起動しないと一覧に出なかった。自動検出するか、更新ボタンを置くかしたい。
  2. 今はコマンドをコピーして端末でユーザーが実行する方式だが、アプリでダウンロードでき、進捗が見られて、モデルの削除もできるとよい。
- 前提（実装済み、`docs/plans/archived/2026-10-15-menu-settings-and-model-switch.md`）:
  - モデル一覧は `StrataInstallation.installedModels()` が Strata ディレクトリ直下の `strata-<tag>.json` を列挙する。`MenuContent` と `SettingsView` の body の中で毎回計算しており、監視対象の状態ではない。ディレクトリに JSON が増えても body の再評価が起きない限り一覧は変わらない。設定画面の「Check」は `installationProblems` と `baseFacts` を更新するだけで、一覧の再計算は副作用でしか起きない。
  - 設定画面の「Install another model」は `SetupCommand.make` が組む `cd "<Strata>" && ./setup.sh --setup --model <MODEL> --no-start` をコピーするだけ（`--yes` は付けず、setup の質問をユーザーが見られるようにする決定）。
  - `PosixProcessLauncher` は posix_spawn で新しいプロセスグループを作り、stdin は /dev/null、stdout/stderr はログファイルへ追記する。`LaunchPlan` は実行ファイル・引数・cwd・環境・ログの URL を持つ。`ServerManager` が所有プロセスの状態機械。
- 確認した事実（2026-10-16、Strata checkout `~/Dev/local/Strata`、ブランチ f-1441 の 296b59d2。データは `~/.config/strata/settings.json` の `data_dir` = `~/Dev/local/Strata-data`）:
  - `setup.sh` → `.venv/bin/python setup.py` → macOS では `subprocess.call([python, metal/setup_mac.py, *argv])`（同じプロセスグループの子）。
  - Mac の setup が `ask()` するのは「Which size?」（`--model` で省略）と「Should the model also read images?」（`--vision yes|no` で省略）の 2 つだけ。`ask()` は非 TTY で入力が EOF なら `fail`（終了）。つまり `--setup --model <MODEL> --no-start --vision no` なら質問なしで非対話実行でき、`--yes` は要らない。
  - 出力は `=== Step N: title ===` の 7 段（1 checking your Mac、2 your choices、3 Python packages、4 the Strata engine (Metal)、5 downloading …、6 preparing the model for Strata、7 writing the start script）。`download()` は 2 秒ごとに `\r  <file>: X.XX / Y.YY GB (NN%)` を flush 付きで出力し、`.part` で再開、完了で `<file>.done` マーク。ステップ 6（experts のコピー、pack、UD 系の repack）に進捗出力はない。
  - ステップ 6 は pack が未作成なら `pgrep -x strata` で稼働中のエンジンを探し、あれば `fail`（repack と pack はディスクを 100 GB 以上動かし、Python が最大 20 GB を持つため、エンジンと並走した 128 GB M5 Max が 2 度フリーズした記録）。作業中は `.preparing.lock` を置き、エンジン側はそれを見て待つ。
  - 32 GiB の Mac（stream かつ RAM < 96 GB）では experts のストリーミングコピー `<shard1>.experts` を書く（IQ3_XXS で 40 GB、M4 で約 3 分）。空き容量が必要量 + 10 GB 未満なら書かずに続行（警告のみ、エンジンは遅くなる）。
  - 空き容量: setup は `download_gb + 6` GB 未満なら警告して続行する。実際の消費は IQ3_XXS で `models/IQ3_XXS` 111 GB + `packs/iq3_xxs` 1.4 GB（download 75.8 GB + experts コピー 40 GB）。アプリのカタログの `downloadGB` は実消費より小さい。
  - setup が書くもの: `<Strata>/strata-<tag>.json`、`run-<tag>.sh`（実行時に `strata-<tag>.log`）、`<data>/models/<MODEL>/`（GGUF 2 本、`.done`、`.experts`、`.experts.done`、途中なら `.part`）、`<data>/packs/<tag>/`。UD 系（shard が 3 本以上）はさらに `<data>/metal/<tag>-metal.gguf`。モデル間で共有し消してはいけないもの: `<Strata>/data/expert-profile.bin`、`<data>/mtp/`、vision の mmproj、`build-metal/`、`.venv`。
  - Strata にモデルの削除コマンドはない。`~/.config/strata/settings.json` は `data_dir` と `installs` だけで、モデルの登録簿はない。
  - `setup.py` は `KeyboardInterrupt` を捕捉して "stopped." で終了する。子ツール（`iq_pack.py`、`stream_experts.py`、`metal_repack.py`）は同じプロセスグループ。途中で止めても安全: ダウンロードは `.part` から再開、pack は `native_experts.txt` を最後に書く完了マーカー（途中で止まった pack は未完成と見なして作り直す）、experts コピーは `.part` に書いて `os.replace`。つまり setup の再実行が常に「続き」になる。
  - 同時実行の守り（Q2 の調査）: setup の守りはステップ 6 の入口での `pgrep -x strata` だけ。`.preparing.lock` は新しいモデルの `models/<MODEL>/` に置かれ、エンジンは自分のモデルファイルのディレクトリのロックしか見ない（`metal/src/engine/window.cpp`）ので、別モデルを稼働中のエンジンには効かない。idle unload でエンジンが落ちている間に setup がステップ 6 を通過すると、次のリクエストで再開するエンジンが pack と並走しうる。この穴は Strata 側では塞がれていない。
  - モデルのディレクトリ名と tag: `tag = FAMILIES[family]["tag"] + model`。qwen 系（Q2_0 / IQ3_XXS / IQ3_S）は接頭辞なしで `models/IQ3_S`、`strata-iq3_s.json`。Unsloth 系（UD-*）は接頭辞 `unsloth-` が付き、`models/unsloth-UD-Q4_K_XL`、`strata-unsloth-ud-q4_k_xl.json`、`model_name` は `qwen3.8-flash-next-unsloth-ud-q4_k_xl`。現在の `ModelPack.tag`（名前の小文字化）は UD 系で合っていない（導入済み判定が外れる既存バグ、計画で直す）。shard 名は qwen 系 `Qwen3.8-Flash-Next-GSQ-RCO-<Q>-0000<i>-of-00002.gguf`、UD 系 `Qwen3.8-Flash-Next-<Q>-0000<i>-of-0000<n>.gguf`（n = 4 または 6）。
  - ストリーミングの判定: `shard1_gb + 8 > ram_gb × 0.75 × 1.0737`（64 GB 未満の Mac）。32 GiB ではすべてのパックがストリーミングになり、RAM < 96 GB なので experts コピーが書かれる。コピーの大きさは setup.py の `MODELS[model]["arena_gb"]`（Q2_0 34.0 / IQ3_XXS 42.9 / IQ3_S 50.3 GB。実ファイルと一致）。ディスク消費の見積もりは「download_gb + arena_gb + pack 約 1.5 GB」、experts コピーにはさらに 10 GB の余裕が要る。
  - Mac の setup が `S.` 経由で呼ぶ関数（`pip_install`、`get_llama_cpp`、`check_shards`、`download`、`refresh_draft_vocab`、`write_config` など）はどれも `ask()` / `confirm_risk()` / `install_build_tools()` を呼ばない（呼ぶのは PC 向けの `build_engine`、`choose_gpus`、`main` など。`setup_mac.py` は自前の `build_engine` を使う）。非 TTY で質問に当たる経路はない。
  - UD 系の `MODELS` にも `arena_gb` がある（UD-Q4_K_XL: 77.0）。UD 系は repack で `metal/<tag>-metal.gguf`（`shard1_gb`、UD-Q4 で 82.6 GB）も書くので、ディスク見積もりはダウンロード + repack ファイル + experts コピー + pack。
- 計画で扱う制約（dig で事実を確認したが、設計判断ではなく実装上の制約として計画に持ち込む）:
  - 端末で動いている setup との競合: ダウンロード中はロックがない（`.preparing.lock` はステップ 6 から）。アプリのジョブのプロセスグループに属さない `setup_mac.py` のプロセスが `pgrep -fl setup_mac.py` で見つかる間は、その `--model` のパック（なければ全パック）の Download と Delete を無効にする（引き取りはしない、拒むだけ）。`.part` の mtime やロックでは pip・再ビルド・shard 検証中や、アプリ自身の Cancel 直後を正しく判定できないので使わない（計画レビューで修正）。
  - ステップ 6 での停止と失敗の区別: setup 自身の停止（`[X]  a Strata engine is running`）も SHA 不一致も exit 1 で、アプリの SIGINT が setup の終了後に届くこともある。終了コードではなくファイルの状態で判定する: 全 shard に `.done` があり設定 JSON がなければ「Downloaded」、それ以外は失敗としてログ末尾の `[X]` 行を出す。
  - 起動に含めた準備中の Stop: その時点の所有プロセスは setup であり、サーバーではない。Stop は setup のグループに SIGINT を送る。準備の時間は `startupDeadline`（600 秒）に数えない（UD の repack は 100 GB 超で超えうる）。
  - 監視の範囲: ディレクトリの vnode 監視は直下の変化しか拾わない。`strata-<tag>.json` は Strata 直下で拾える。`models/<MODEL>/` の中の `.done` はモデルディレクトリごとの監視を足すか、画面を開いたとき・Check・アプリのダウンロード完了時の読み直しに任せる。
  - 進捗は shard 単位: `X / Y GB (NN%)` は 1 ファイル分。UD 系は 4〜6 本なので、`.done` 済みの shard のサイズを足して全体の割合にする。
  - ゴミ箱への移動では空きが増えない: Delete 後の空き容量表示にその旨を添える。
  - Download はステップ 3〜4（Python パッケージ、エンジンの確認・再ビルド）も暗黙に通る。checkout が変わっていればエンジンが再ビルドされる（Strata の挙動）。README に書く。
  - データディレクトリの解決は setup の `data_folder()` と同じ: `~/.config/strata/settings.json` の `data_dir`、なければ `<Strata>/../Strata-data`。
  - 作業順: 部分 1（監視対象の一覧 + ディレクトリ監視）を最初のタスクにする（独立していて、今の不便の直接の原因。ダウンロード完了の反映もこれに依存する）。
- 制約:
  - AGENTS.md の不変条件「Strata checkout・モデルファイルに書かない」「setup のインストール・実行をしない」は前回の dig（`docs/dig/2026-10-15-popover-sliders-model.md`）の対象外として決めたもの。今回はユーザーの要望で見直す対象であり、契約の変更なので新しい計画で扱う。
  - 維持するもの: 自動再起動しない、アプリが起動していないサーバーは止めない、127.0.0.1 のみ、クライアント設定に触れない。
- 作業ツリーに今回と無関係な未コミット変更（Context の段の 262144 への拡張、`Assets.xcassets`、`default.profraw`）がある。今回の作業とは分けて扱う。

## 決定事項
- アプリ内のモデル取得は、Strata の setup をアプリが所有プロセスとして実行する: `.venv/bin/python setup.py --setup --model <MODEL> --no-start --vision no` を、サーバーと同じ仕組み（posix_spawn、専用プロセスグループ、stdin は /dev/null）で起動し、出力は `~/Library/Logs/StrataMenubar/setup.log` へ追記する。進捗はそのログと `.part` ファイルの大きさから表示する。Strata 側への書き込みは Strata の setup 自身が行い、アプリ本体は書かない。アプリ独自のダウンローダーは作らない。
  - 理由: 要望（アプリ内で進捗が見える）を満たす唯一の案で、setup が非対話で走ること、再開・完了マークを Strata が持つこと、既存の起動・所有の仕組みが流用できることを確認済み。
  - 不変条件の書き換え: 「アプリ本体は Strata checkout・モデルファイルに書かない。書くのは、明示操作で起動した Strata の setup だけ」とする（計画で AGENTS.md を更新）。
  - 出典: Q1 → A
- ダウンロードとサーバーは独立させる。ダウンロードはサーバーの状態に関係なくいつでも開始でき、サーバーの起動・停止・再起動もダウンロード中に自由にできる。アプリがサーバーを勝手に止めることはしない。
  - ダウンロード完了時にサーバーが止まっていれば、setup はそのまま準備（pack、experts コピー）まで進み、モデルは「導入済み」になる。
  - ダウンロード完了時にサーバー（External Strata 含む）が動いていれば、アプリは setup の出力に `=== Step 6: preparing the model for Strata ===` が現れた時点でプロセスグループに SIGINT を送って止め、モデルを「ダウンロード済み（初回起動時に準備）」として扱う。Strata 自身の `pgrep` の守りは backstop で、idle unload の穴はこの割り込みで塞ぐ。
  - 準備はモデルごとに初回だけ必要（完了マーカーで再実行時はスキップされる）。ダウンロード済みのモデルを選んで Start / Stop and Apply Saved Settings / Apply and Restart Server を押したときに、停止 → setup の再実行で準備（数分、進行中と表示）→ サーバー起動、を一続きに行う。Prepare ボタンは置かない。準備中だけ Start は無効。
  - 「ダウンロード済み」はファイルから判定する（`<data>/models/<MODEL>/` に `.gguf` があり、すべてに `.done` があって `.part` がない）。モデルのピッカーは導入済みに加えてダウンロード済みも選べるようにし、その旨を表示する。
  - 理由: 「落としておいて、使いたくなったら切り替える」使い方に合い、操作が増えない。準備をエンジンと並走させないという Strata の制約は、再起動の「止まっている瞬間」に準備を挟むことで満たせる。
  - 出典: Q2 → ユーザーの指摘（ダウンロードとサーバーを分離、準備は初回だけなので初回起動時に行う）
- 進捗表示: 設定画面の「Models」節に、ダウンロード中のパックの行として進捗バーと Cancel ボタンを置く。ダウンロード中（ステップ 5）は `setup.log` の `X.XX / Y.YY GB (NN%)` から割合を出し、それ以外のステップは `=== Step N: title ===` の段階名を不確定バーで出す。メニューにも 1 行（例: 「Downloading IQ3_S: 45% (12.3 / 75.8 GB)」「Preparing IQ3_S…」）を出し、クリックで設定画面を開く。完了・失敗はメニューの同じ行に残し、失敗時はログ（`setup.log`）を案内する。
  - 理由: 数時間かかる処理なので、メニューを開くだけで様子が分かる。設定画面は開始・中止・詳細、メニューは一目で見る場所、という既存の役割分担と同じ。
  - 出典: Q3 → A
- 中止: Cancel はプロセスグループに SIGINT（setup は `KeyboardInterrupt` で "stopped." 終了）。出なければサーバーと同じ段取りで SIGTERM → SIGKILL。途中のファイル（`.part`、作りかけの pack）は残し、次の Download（同じコマンド）で続きから再開する。同時に走らせるダウンロードは 1 つ。
  - 出典: Q4 の前提として提示、異議なし
- 終了: ダウンロード（準備を含む setup）の実行中に Quit したら、サーバー稼働中と同じく確認する:「ダウンロード中です。終了するとダウンロードを止めます（次回は続きから再開できます）」。Quit なら setup を止めてから終了、Cancel なら終了しない。サーバーも動いていれば 1 つのダイアログにまとめる。setup を残したまま終了しない。
  - 理由: 数時間の処理を黙って止めない。取り残したプロセスは引き取らない契約に反する。
  - 出典: Q4 → A
- ディスク容量: Download の前に、アプリが見積もり（download_gb + experts コピー（arena_gb、ストリーミングする Mac のみ）+ pack 約 1.5 GB）とデータディレクトリの空きを表示し、空きが「見積もり + 10 GB」に満たなければ Download を無効にして理由を出す。カタログに `arena_gb` 相当（experts コピーの大きさ）を加える。ストリーミング判定は setup と同じ式（`shard1_gb + 8 > ram_gb × 0.75 × 1.0737`、64 GB 未満の Mac）。setup 自身の警告はログに残るだけ。
  - 理由: 100 GB 超の書き込みを途中で詰まらせない。experts コピーが黙って省かれて遅いモデルになる事故を防ぐ。
  - 出典: Q5 → A
- 削除: 設定画面の Models 節の各モデル（導入済み、ダウンロード済み）に Delete を置く。消す対象をファイルと合計サイズで列挙して確認したうえで、ゴミ箱へ移動する（`FileManager.trashItem`）。完全削除はしない。
  - 対象は `strata-<tag>.json` の `--pack` / `--native` / `--ple-gguf` から辿る: `models/<MODEL>/` 一式（shard、`.done`、`.experts`、`.experts.done`、`.part`）、`packs/<tag>/`、`strata-<tag>.json`、`run-<tag>.sh`、`strata-<tag>.log`、アプリの `strata-<tag>.run.json`。UD 系は `data/metal/<tag>-metal.gguf` とそのマーク・ロックも。ダウンロード済み・未準備のモデルは `models/<MODEL>/`（と作りかけの pack）。共有物（`data/expert-profile.bin`、`mtp/`、mmproj、`build-metal/`、`.venv`）は触らない。
  - そのモデルが稼働中（アプリのサーバー、External Strata の `model_name` が一致）か、ダウンロード・準備中は Delete を無効にして理由を出す。
  - 保存済みの選択モデルを消しても設定は触らず、既存の「(not installed)」表示と起動時の案内に任せる。
  - これはアプリ本体が Strata のデータに手を入れる唯一の操作。不変条件にその旨を明記する。
  - 理由: 100 GB 超を扱うので取り消せる方式にする。レイアウトは Strata の版で変わりうるため、実ファイルを列挙して確認を挟む。
  - 出典: Q6 → A
- モデルの検出: 導入済み・ダウンロード済みの一覧を監視対象の状態（`@Observable`）にし、Strata ディレクトリ直下（`strata-*.json`）とデータディレクトリの `models/` を `DispatchSource` のファイルシステム監視で見て、変化したら読み直す。設定画面を開いたとき、Check を押したとき、Strata ディレクトリの入力を変えたときにも読み直す。アプリ内のダウンロード・準備・削除の完了時も読み直す。専用の更新ボタンは置かない。
  - 理由: 端末から入れた場合も Finder で消した場合も操作なしで一覧が合う。更新ボタンは監視があれば押す場面がない。
  - 出典: Q7 → A
- 設定画面: 「Model」節と「Install another model」節を 1 つの「Models」節に統合する。先頭に起動するモデルのピッカー（導入済みとダウンロード済みを選べる）。続けてカタログの 6 パックを 1 行ずつ並べ、各行に状態（Installed / Downloaded, prepared at the first start / Downloading NN% / Preparing / Not downloaded / 失敗）、サイズの案内（ダウンロード、GPU がマップする容量、必要メモリ、推奨 RAM、ディスク消費の見積もり）、操作（Download / Cancel / Delete）を置く。節の末尾にデータディレクトリの空き容量と `setup.log` を開く導線。Copy Command は廃止し、`SetupCommand` も削除する。
  - 理由: 「選ぶ」「落とす」「消す」が同じ一覧で完結する。Copy Command はアプリが同じコマンドを実行するので役目が重なる。端末で実行する手順は README に残す。
  - 出典: Q8 → A
- 前提の確認（Q9 → A で合意）:
  - UD 系（推奨 128 GB）も一覧に出し、メモリ不足では止めない（Strata と同じ「言うが拒まない」。止めるのはディスクの確認だけ）。
  - setup は `.venv/bin/python setup.py --setup --model <MODEL> --no-start --vision no` を直接起動する（`setup.sh` は経由しない。`.venv` は導入確認で必須済み）。
  - 起動に含めた準備は Starting の状態行に「preparing <model>…」と出す。準備が失敗したらサーバーは起動せず Error にして `setup.log` を案内する。
  - `setup.log` は他のログと同じ場所（`~/Library/Logs/StrataMenubar/`）・同じローテーション。メニューに「Open Setup Log」を足す。
  - 端末で途中まで落としたモデル（`.part` があり、アプリのプロセスがない）は「Partially downloaded」と表示し、Download で続きから再開できる。
  - 作業の順序: 無関係な未コミット変更（Context 262144 への拡張、`Assets.xcassets`）は先に別コミットにし、`default.profraw` は追跡しない。
  - 出典: Q9 → A

## 対象外
- 画像入力（`--vision no` 固定。画像エンコーダーの導入は扱わない）。
- setup の `--update` / `--build`（エンジンの更新・再ビルド）や `--context` など、ダウンロード以外の setup オプション。
- 複数ダウンロードの同時実行（1 つずつ）。
- Strata 本体のインストール・更新、端末で始めた setup プロセスの引き取り。
- アプリ独自のダウンローダー（URL・リビジョン・SHA の複製）。
- 自動再起動、アプリが起動していないサーバーの停止、クライアント設定の書き換え（維持）。

## 未決・保留
- （なし）

## 撤回・置換済み
- （なし）

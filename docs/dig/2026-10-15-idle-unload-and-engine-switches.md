# dig log: Idle unload とエンジンスイッチ 5 項目の設定化

## 目的・前提・制約
- 目的: Strata の次の 5 項目を StrataMenubar から設定できるようにする。この Mac（32 GiB、ストリーミング構成、MTP なし）で意味がない項目も、他のユーザー・他の Mac では意味があるので含める。
  1. Idle unload（server の `idle_unload_s` / `--idle-unload`）
  2. `fit_max_tokens`（server の config 真偽値 / `--fit-max-tokens`）
  3. `--spec N`（エンジン引数、base config の `args` に setup が必ず書く）
  4. `STRATA_METAL_PROMPT_CHUNK`（エンジン env）
  5. `STRATA_METAL_KEEP_FREE_GB`（エンジン env）
- 経緯: ユーザーが docs/MAC.md の「Switches (for testing)」を見て「どれを設定できるべきか、全部か」と質問。アシスタントの評価（全部は出さない。上記 5 項目のうち Idle unload と fit_max_tokens は価値あり、--spec / PROMPT_CHUNK / KEEP_FREE_GB は条件付き、他は出さない）に対し、ユーザーが 5 項目を採用すると決定。
- 確認した事実（ローカル Strata checkout `~/Dev/local/Strata`、commit 296b59d、2026-10-15）:
  - 既定値:
    | 項目 | 渡し方 | 未指定時の既定 | 備考 |
    | --- | --- | --- | --- |
    | Idle unload | config `idle_unload_s`（秒、float）または `--idle-unload` | 0 = しない | server.py 6839 行。CLI が config より優先。アンロードはエンジンプロセスを終了させ、次のリクエストで再ロード（`POST /load` / `/unload` もある）。`/health` は `loaded: false` を返す |
    | fit_max_tokens | config `"fit_max_tokens": true` または `--fit-max-tokens` | false = 400 で拒否 | `cfg.get("fit_max_tokens") is True` 判定。真偽値のみ |
    | `--spec N` | base config `args` | エンジン自体は Metal で 2（generate.cpp 562 行）。setup_mac.py は必ず `--spec` を書く（2、ストリーミング+MTP なら `STREAM_SPEC = 3`） | 上限 8（kVerifyMaxT）。`--suffix-draft > 0` のときエンジンが内部で +2。MAC.md の計測: 2 が混合テキストで最良、3〜4 はプロンプト次第、5〜6 は遅い。MTP ドラフト層がない構成では効果なし |
    | `STRATA_METAL_PROMPT_CHUNK` | config `env` | 計算値: 常駐なら 2048、ストリーミングなら RAM 96 GB 以上で 4096、未満で 1024（window.cpp 2022 行）。別経路 prompt_chain.inc は 2048、64〜8192 にクランプ | 64 の倍数に丸め。MAC.md の「default 2048」は一経路の値。小さい Mac で長いチャンクはバッファ（最大 4.3 GB）が arena を食う |
    | `STRATA_METAL_KEEP_FREE_GB` | config `env` | max(7 GB, RAM の 15%)（arena_budget.h 81 行）。32 GiB なら 7 GB | **`STRATA_METAL_ARENA_GB` が設定されていると無効**: `arena_budget` は `arena_gb >= 0` なら即その値を返し、`arena_grow` / `arena_shrink` も素通り。ストリーミング時のみ意味がある |
  - Idle unload のサーバー側挙動（server.py）: `loaded()` はエンジンプロセスの生存。アンロードは `StrataEngine.unload()`（エンジン終了、`unloaded = True`）、次のリクエストで `restart()`。`/health` は `status / max_context / model / images / api_key / image_generation / loaded / service` だけで、**「idle でアンロード中」と「再ロード中」「エンジンが落ちて再起動中」を区別する情報はない**（`/v1/status` の `auto_load`、`/props` の `is_sleeping` も同様）。アイドル監視は `max(1, min(30, N/4))` 秒ごとなので、実際のアンロードは最終リクエストから N〜N+30 秒後。`last_request_at` を更新するのは生成・`/load`・slot 保存・画像リクエストだけで、`/health` は更新しない（アプリの 10 秒ごとの監視はアンロードを妨げない。計画作成時に確認）。
  - `--spec N` のエンジン側挙動（generate.cpp）: ヘルプは「the MTP drafter's verify window: how many tokens it proposes per check」。MTP は `--mtp` があり `spec >= 2` のときだけ動く（3501 行）。検証カーネルの上限は `kVerifyMaxT = 8`。`--mtp` がない config（この Mac の `strata-q2_0.json`）では `--spec` は効かない。
  - `STRATA_METAL_STREAM` の補完（base に無いとき 1 を書く）は最初の実装（8208060）で入り、`RunConfigTests` が検証している。setup_mac.py は常に `"1"` か `"0"` を書くので、補完が効くのは setup 以外で書かれた config だけ。
  - アプリの現状:
    - `StrataSettings` は strataDirectory / model / expertCacheGB / maxContext / port。`RunConfig.make` は `--max-context`、`STRATA_METAL_ARENA_GB`（常に書く）、`STRATA_METAL_STREAM`（base に無いときだけ 1）、`log`、`port` だけを変更し、他の `args` / `env` / キーはそのまま写す。→ ユーザーが base JSON に自分で書いたスイッチは通る。
    - サーバーは `--engine strata --config <run.json> --host 127.0.0.1 --port N` で起動。
    - 状態機械: 起動時は `/health` の `loaded: true` を最大 600 秒待つ（1 秒間隔）。稼働後は 10 秒間隔の monitor で `/health` を見て `RunningInfo.health` を更新するだけ（`.notLoaded` は「— health check: model not loaded」と表示、動作はしない）。外部サーバーは `loaded: false` を「(loading)」と表示。
    - メニュー: 状態行、未反映表示、Model ▸ / Expert cache ▸ / Context ▸ のサブメニュー（選択で即保存）、Start / Stop / Stop and Apply、Open Chat、ログ、Settings…、Quit。
    - 設定画面: 下書き + Apply / Revert。稼働中は「Started with: model, cache, context, port」を表示し、「Apply and Restart Server」/「Stop and Apply Saved Settings」。
    - `SettingsStore` は UserDefaults にキーごとに保存。
- 制約（AGENTS.md の invariants、維持）: Strata checkout・モデル・クライアント設定を書き換えない。run config は管理キーだけ変更。保存は次回起動に反映、再起動は明示操作のみ。自動再起動なし。127.0.0.1 のみ。

## 決定事項
- 上記 5 項目を設定できるようにする。この環境で意味がない項目（`--spec`、MTP なし）も含める。
  - 理由: ユーザーによっては意味がある。
  - 出典: dig 開始前のユーザー発言
- Expert cache は「Auto / 固定 N GB」の二択にする。Auto では run config に `STRATA_METAL_ARENA_GB` を書かず、エンジンが arena を決める（`KEEP_FREE_GB` は Auto のときだけ効く）。新規ユーザー（保存値なし）の既定は Auto。保存済みの `expertCacheGB` がある既存ユーザーは固定のまま（移行処理なし）。README の「5 GB で約 13 GB」の実測は固定モードの説明として残す。
  - 理由: 5 GB はこの 32 GiB Mac で測った機種固有の値で、他の Mac に根拠がない。Auto は Strata 自身の既定動作（RAM と空きメモリから決め、段階フィルで縮める）。`KEEP_FREE_GB` の既定（max(7 GB, 15%)）を潰さないため、既定で `KEEP_FREE_GB` を明示値にはしない。
  - 出典: Q1 → A
- `KEEP_FREE_GB` は「Engine default」の選択肢 + 1 GB 刻み（1 GB〜物理メモリ）。Engine default は run config に書かない。表示は「7 GB or 15% of RAM, whichever is more (N GB on this Mac)」と計算値を添え、Strata の docs（MAC.md / arena_budget.h）による旨を出典として添える。7 GB 未満は警告（34 分の soak で 5 GB 残しでは arena 充填中に 93 MB が swap out した実測が根拠）。Auto モードのときだけ有効。
  - 理由: 既定の実値がないと「既定より多く／少なく残す」判断ができない。式は docs に明記され、`MemoryBudget` の物理メモリから 1 行で計算できる。転記のリスクは既存の注記（`StrataModelCatalog`、1.36 GB）と同じ扱い。
  - 出典: Q2 → A
- Idle unload で `loaded: false` になった稼働中サーバーは `ServerState.running` のまま。idle unload 付きで起動したサーバー（`RunningInfo.settings` で判定）では `loaded: false` を「Running on port N: model, context C (model unloaded after idle; loads on the next request)」のように中立に表示し、health 異常扱いにしない。idle unload なしで起動したサーバーは従来どおり「— health check: model not loaded」。Open Chat / Stop / Quit / 未反映判定は変更なし。再ロード中も同じ文言になる（サーバーが区別する情報を返さないため）ことは注記する。
  - 理由: プロセス所有も操作も変わらない。新しい state case は文言だけの違いに対して過剰。起動設定にかかわらず中立にすると、idle unload なしの人からエンジン停止の兆候を奪う。
  - 出典: Q3 → A
- Idle unload の値は分単位の離散値: Never / 5 / 10 / 15 / 30 / 60 / 120 min。Never（0）は run config に書かない（= サーバー既定「しない」）。一覧にない保存値は Context と同様に現在値の項目として並べる。設定画面も同じ一覧のポップアップ。
  - 理由: サーバーのアイドル判定は N/4 秒（最大 30 秒）刻みで秒精度に意味がない。再ロードは約 3 秒（この Mac、ファイルキャッシュ温）で、数分未満は損失が大きい。Context の段と同じ仕組みで、設定画面のポップアップと、メニュー・Started with の表示が一つの一覧で揃う（Q7 以降、メニューは表示のみ）。
  - 出典: Q4 → A
- `--spec N` は「As set up (N)」の選択肢 + 2〜8 の整数。As set up は base config の `args` を触らない（N は base から読んで表示）。base config に `--mtp` がなければ「This model's config has no MTP draft layer (--mtp); --spec has no effect」の注記を出すが、選択肢は無効化しない。5 以上に警告（M5 Max の計測で 5〜6 は遅い）。
  - 理由: 「管理キー以外は触らない」契約を保ち、setup の RAM に応じた判断（2 / 3）を既定として見せる。無効化しないのは「他のユーザーには意味がある」方針と、`--setup` で MTP を足した config に自動で追従させるため。常に数値を書く案は setup の 3 を 2 で上書きする。
  - 出典: Q5 → A
- `STRATA_METAL_PROMPT_CHUNK` は「Auto (N on this Mac)」の選択肢 + 1024 / 2048 / 4096 / 8192。Auto は run config に書かない。N は物理メモリと base config の `env.STRATA_METAL_STREAM` から計算（常駐 2048、ストリーミングは 96 GB 以上で 4096、未満で 1024）。`STRATA_METAL_STREAM` が base にないときは「Auto (the engine decides by model size)」と数値なし。ストリーミング config でこの Mac の既定より大きい値に警告（4096 ではプロンプト処理中に 4.3 GB のバッファが arena から取られる実測を根拠に）。
  - 理由: `KEEP_FREE_GB` と同じ「既定の実値を見せる」方針。選択肢は MAC.md の計測値（1024 / 2048 / 4096）にエンジン上限 8192 を足した 4 段で足りる。
  - 出典: Q6 → A
- メニューから設定は変更しない。メニューは現在の各設定値を読み取り専用で分かりやすく表示するだけにし、設定変更はすべて設定画面（下書き + Apply）で行う。Model ▸ / Expert cache ▸ / Context ▸ のサブメニュー（選択で即保存）は廃止する。Start / Stop / Stop and Apply などの操作はメニューに残す。
  - 理由: メニューバーから頻繁に変えたいのはサーバーのオンオフだけ。「頻度」でサブメニューの範囲を線引きする理屈は成り立たない（Expert cache / Context も一度決めたら触らない）。
  - 出典: Q7 の議論でのユーザー決定
  - 影響: AGENTS.md の invariant「the menu saves at once, the settings window via Apply」と README の Use / Settings の記述を改める（計画で扱う）。
- メニューの読み取り専用表示は保存値（次回起動に使う値）を 1 項目 1 行で出す。Model、Expert cache（Auto / N GB）、Context、Port、Idle unload は常に出し、Keep free / Spec / Prompt chunk / Fit max tokens は既定（Engine default / As set up / Auto / off）でないときだけ出す。稼働中のサーバーの起動時の値と違う行には「(running: X)」を添える。行を押すと設定画面が開く。状態行（稼働中の model / context / port）と「Saved settings differ from the running server」の一行は維持。
  - 理由: 1 項目 1 行で分かりやすく、既定のままのチューニング項目で行数を増やさない。既定でない項目だけ現れる規則で「何かを変えてある」ことが目に入る。
  - 出典: Q8 → B
- `STRATA_METAL_STREAM` の補完をやめる。base の `env` に無ければ run config にも書かず、エンジンがモデルサイズで決める。`RunConfigTests` の該当テストと README の管理キー説明を改める。
  - 理由: Auto 化の趣旨（未指定はエンジンの既定）と揃う。setup は必ず書くので補完が効くのは手書き・古い config だけで、そのとき常駐できる Mac にも強制ストリーミングを課してしまう。ストリーミング必須の Mac はエンジン自身がサイズで判断する。
  - 出典: Q9 → A
- 実装の細部（Q10 で合意）:
  - Auto / 固定の UI: 設定画面は「Size the expert cache automatically」のトグル。Auto ではスライダーを無効化し Keep free のポップアップを有効化、固定ではその逆。
  - 渡し方: Idle unload と fit_max_tokens は CLI 引数ではなく run config のキー（`idle_unload_s`、`fit_max_tokens`）で渡す。理由: run.json が起動設定の正本として自己記述的になり、README の管理キー一覧に並べられる。
  - `fit_max_tokens`: 設定画面のチェックボックス、既定オフ、true のときだけ run config に書く。注記に「プロンプト自体が context を超える場合は救えない（max_tokens を切り詰めるだけ）」を添える。
  - 設定画面の構成: 「Memory and context」に Expert cache（Auto トグル + スライダー）、Keep free、Context、Prompt chunk。新設「Server」に Port、Idle unload、Fit max tokens。新設「Engine」に Spec（`--mtp` なしの注記つき）。警告・注記はこれまでどおり `StrataSettings.validate` に集約。
  - 「Started with」表示と未反映判定: 新項目はすべて `StrataSettings` のフィールドにするので、等値比較による未反映判定には自動で含まれる。「Started with」の文字列はメニューと同じ規則（Model / Expert cache / Context / Port / Idle unload は常に、チューニング項目は既定でないときだけ）。
  - 管理キーの一覧（README）: `--max-context`、`--spec`（変更時のみ）、`STRATA_METAL_ARENA_GB`（固定時のみ）、`STRATA_METAL_KEEP_FREE_GB`（Auto で指定時のみ）、`STRATA_METAL_PROMPT_CHUNK`（指定時のみ）、`idle_unload_s`（Never 以外）、`fit_max_tokens`（true のみ）、`log`、`port`。`STRATA_METAL_STREAM` は一覧から外す。
  - 出典: Q10 → A
- 未反映判定（「Saved settings differ」「Stop and Apply」）は有効な値で比べる。Auto のときの固定値 `expertCacheGB` と、固定のときの `keepFreeGB` は run config に書かれないので比較から外す。設定画面の下書きの dirty 判定は全項目のまま。
  - 理由: run config が同じなら再起動を促す意味がなく、「違いがあればどこかの行に (running: X) が付く」という Q8 の趣旨を守れる。
  - 出典: implement 中のユーザー決定（Unit B 独立レビューの decision required: 潜在値の差で differ が出るがどの行にも差分が付かない）

## 対象外
- 5 項目以外のスイッチ（`STRATA_HC_Q8`、`FUSE` / `LAZY_FOLD` / `PARTIAL` / `ROUTE` / `MTP_Q8` / `MTP_CHAIN` / `PROMPT=window`、`TRACE` / `PROFILE` / `KPROF`、`WIRE_ARENA` / `LEAVE_SHARE`、`IGNORE_REPACK`、`CONTIG`、`KEEP_HOST_WEIGHTS`）、`--host` / `--api-key`（invariant）、`--vision` / `--mtp` / `--draft-vocab`（setup 時に決まる）、`--lazy`。
  - 根拠: アシスタントの評価に対しユーザーが 5 項目を選び、Q10 で対象外として明示的に合意。
  - これらは base JSON の `env` / `args` に書けばアプリが素通しする、という運用で足りる。
- メニューからの Unload Now / Load Now（`POST /unload` / `/load`）操作。
  - 出典: Q10 → A

## 未決・保留
- （なし）

## 撤回・置換済み
- 前回の dig（`2026-10-15-popover-sliders-model.md` Q9 → B）の「Model ▸ / Expert cache ▸ / Context ▸ のサブメニューで選ぶと保存」は、Q7 の議論でのユーザー決定（メニューは読み取り専用の表示、変更は設定画面）に置き換えた。

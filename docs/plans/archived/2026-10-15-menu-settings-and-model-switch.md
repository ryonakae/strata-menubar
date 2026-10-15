# Menu Settings and Model Switch Implementation Plan

dig log: [docs/dig/2026-10-15-popover-sliders-model.md](../dig/2026-10-15-popover-sliders-model.md)（決定事項・対象外・撤回済みの正本）

## Requirements

導入済みの Strata モデルの切替と、Expert cache / Context の変更を、メニューバーのメニューと設定画面から行えるようにする。前回の実装（`docs/plans/archived/2026-10-14-strata-menubar.md`）の制約はそのまま守る：Strata 本体・モデル・Pi 設定を書き換えない、自動再起動しない、保存は次回起動に反映し、稼働中は「Stop and Apply」で明示的に適用する。

- メニューは今の SwiftUI `.menu` スタイルのまま。「Model ▸」「Expert cache ▸」「Context ▸」のサブメニューで選択肢を選ぶと保存される。稼働中に保存値が実設定と異なれば、従来どおり未反映表示と「Stop and Apply Saved Settings」を出す。
- Model の選択肢は、Strata ディレクトリ直下にある setup 済みの `strata-<tag>.json` の一覧。設定にはファイル名の stem（`strata-q2_0.json` → `q2_0`）を保存し、表示は JSON の `model_name`。未保存時の既定は `q2_0` があればそれ、なければ一覧の先頭。保存済みの tag の JSON がなくなっていれば、導入済み一覧を添えたエラーにする。Q2_0 専用のチェック（`model_name == qwen3.8-flash-next-q2_0`）は廃止し、選んだ JSON に `model_name`・`exe`・`args`・参照ファイルがあることだけを確認する。
- Expert cache の選択肢は 1 GB 刻み、下限 1 GB、上限は実行中の Mac の物理メモリ量（GiB、32 GiB なら 32）。禁止はせず、物理メモリの 50% 超（32 GiB なら 17 GB 以上）と 2 GB 未満で警告する。文言に根拠（割合、約 0.8 GB で失敗しプロンプト用 1.36 GB が必要という実測）を添える。
- Context の選択肢は 1024 / 2048 / 4096 / 8192 / 16384 / 32768 の 6 段。8192 超（未検証でメモリ増）と 2048 未満（Pi の maxTokens 2048 が入らない）の警告文は維持する。
- 設定画面：Expert cache と Context はスライダー（同じ範囲・段）、Model はポップアップメニュー。これらとポート・ディレクトリは下書きを編集し、「Apply」で保存する（検証エラーがあれば Apply 不可、「Revert」で保存値に戻す）。未適用の変更があるままウィンドウを閉じようとしたら破棄確認ダイアログ（Discard Changes / Keep Editing）を出す。稼働中は「Apply and Restart Server」（保存して再起動）を置き、下書きが保存済みと同じで保存済みが実設定と異なるときは「Stop and Apply Saved Settings」。どちらも選択中モデルの導入確認が失敗している間は無効。注記として「この Mac では 5 GB で起動時のフットプリント約 13 GB」の実測を事実として書く。（当初の「即時保存・Save / Revert 廃止」はユーザーの決定で置換。dig log 参照。）
- 設定画面に、別モデルを取得・導入するための案内を置く：docs/MAC.md の Mac 向け一覧（Q2_0 / IQ3_XXS / IQ3_S / UD-Q4_K_XL / UD-Q5_K_XL / UD-Q6_K_XL、GPU がマップするファイルの容量、必要メモリの目安、推奨 RAM、setup.py のダウンロード容量）をアプリに固定で持ち、ポップアップメニューで選ぶと `cd "<Strataの場所>" && ./setup.sh --setup --model <MODEL> --no-start` が組み上がる。導入済みのものには印を付ける。コマンドはボタンでクリップボードへコピーできる。`--yes` は付けない。
- Pi の注記に「モデルを変えると `/v1/models` のモデル ID（`model_name`）が変わるので `models.json` の `id` も合わせる」を加える。
- 対象外：アプリによるモデルの取得・setup の実行、`.window` スタイルのポップアップ、AppKit でのメニュー作り直し、自動再起動、Strata 本体・モデル・Pi 設定の書き換え。

## Implementation Decisions

- `StrataSettings` に `model: String`（tag）を追加し、`SettingsStore` は UserDefaults に `model` キーがなければ、保存済みディレクトリの導入済み一覧から既定を解決する（`q2_0` があるか一覧が空なら `q2_0`、なければ先頭の tag。保存はしない）。`StrataSettings.default.model == "q2_0"`。既存の `ServerManager` / `RunningInfo.settings` は変更せず、`settings` の等値比較に tag が含まれることで未反映判定が model を含む。
- 物理メモリ依存の値は `MemoryBudget`（`physicalMemoryGiB`、`cacheRange: 1...physicalMemoryGiB`、`cacheWarningAboveGB = physicalMemoryGiB / 2` の切り上げ）として一か所に置き、`ProcessInfo.processInfo.physicalMemory` から作る。`StrataSettings.validate(memory:)` に渡してテストでは固定値を使う。既定引数で現在の Mac を使う。
- Context の段は `ContextSteps.values = [1024, 2048, 4096, 8192, 16384, 32768]` として一か所に置き、スライダーは段の index（0…5）を動かして値へ写す。保存済みの値が段にない場合（旧設定の 6144 など）は、スライダーは最も近い段を示し、保存値は触らない（ユーザーが動かすまで変えない）。
- `StrataInstallation` はルートだけを持ち、`installedModels()` で `strata-*.json` を列挙して `InstalledModel(tag:, modelName:, configURL:)` を返す（`.run.json` は対象外、`model_name` が読めない JSON は `modelName` に stem を入れて一覧に残す）。`check(model tag:)` が選んだ JSON を検証し、tag の JSON がなければ「導入済み: q2_0, ...」を含む 1 件の問題を返す。
- `AppPaths.runConfig(for tag:)` → `strata-<tag>.run.json`。`StrataLaunchPlanner.makePlan` は `settings.model` の JSON をベースに読み、`--config` にその tag の run config を渡す。`RunConfig.make` は変更しない。
- 案内の固定一覧は `StrataModelCatalog`（`name`、`mappedFileGB`、`needsAboutGB`、`recommendedFromGB`、`downloadGB`、`note`）として docs/MAC.md と setup.py の数値を転記する。`SetupCommand.make(strataDirectory:model:) -> String` が `cd "<path>" && ./setup.sh --setup --model <MODEL> --no-start` を返し、パスの `"` と `\` はエスケープする。クリップボードは `NSPasteboard.general` に `clearContents()` 後 `setString(_:forType: .string)`。
- メニューのサブメニューは `Menu { Picker(selection:) { … }.pickerStyle(.inline) }` で作り、選択の `set` で `settingsStore.save` する。`.menu` スタイルではメニューを開くたびに内容が評価されるので、導入済み一覧はメニュー内容の評価時に `installedModels()` を呼んで取得する（ディレクトリ直下の数ファイルの列挙なので同期でよい）。
- 設定画面は `@State` の下書き `draft: StrataSettings` を編集し、「Apply」で `settingsStore.save(draft)`。ポートは文字列の下書きから解釈し、数値でなければエラー表示。メニューから保存されたとき、下書きが旧保存値と同じなら新しい保存値に追従し、編集中なら下書きを保つ。閉じる操作は `NSViewRepresentable` でウィンドウの `NSWindowDelegate` を差し替えて `windowShouldClose` を横取りし（他の delegate 呼び出しは元の delegate へ転送）、未適用なら `NSAlert` のシートで確認してから閉じる。
- 警告・エラーの文言は `StrataSettings.validate` に集約し、設定画面はそれを表示するだけにする。

## Tasks

Review base commit: `60edd37`。

### Review log

- 全体（Task 1〜4、`60edd37..815ecca`）：独立レビュー（read-only agent）。blocking/high 1件を採用：未保存時の既定モデルで「`q2_0` がなければ導入済み一覧の先頭」が未実装（`SettingsStore` が無条件に `q2_0`）。修正：`model` キーがないときは Strata ディレクトリの導入済み一覧を見て、`q2_0` があるか一覧が空なら `q2_0`、なければ先頭の tag。あわせて medium/low のうち、Check ボタンが入力中のパスを確認しない退行、README の文言（テキスト欄の保存契機、「Stop and Apply」は差異があるときだけ）、Plan に挙げたテストの不足（`model_name` 欠損 JSON、`strata-q2_0.run.json` の名前の固定、`\` のエスケープ、奇数 GiB の切り上げ）を修理として採用。decision required 2件はユーザーが決定：入力未確定のディレクトリ／ポートはウィンドウを閉じると破棄（README に明記）、導入確認が失敗している間は「Stop and Apply」をメニュー・設定画面とも無効化（メニューには先頭の問題を表示）。残りの medium/low は completion report に記載。
- 再レビュー（`1eac629`・`c632c8c`）：blocking 解消。新規 high 1件：Keep Editing に Esc の keyEquivalent を付けたことで Return の既定ボタンが消えた（NSAlert は 1 ボタン 1 キー。レビュー担当の提案が誤り）。correction が新しい blocking を生んだため停止してユーザーに確認 → 「Return を Keep Editing に戻す」を選択。修正：Esc の割り当てを削除（Esc は無反応）。
- 再レビュー（`4e1ebd8`）：採用した指摘はすべて resolved。新規 blocking/high 1件：終了経路で `discard()` を呼ぶため、⌘Q の確認で Discard を選んだ後にサーバー停止確認で Cancel すると下書きだけが消える。correction が新しい blocking を生んだため停止してユーザーに確認 → 「終了経路の discard をやめる」を選択。修正：`AppDelegate` は確認だけ行い下書きに触れない（`SettingsDraftState` は `isDirty` のみ）。あわせて medium の Esc キー（Keep Editing に `keyEquivalent` Esc）を採用。
- full review（`c8a53f3`、設定ウィンドウの下書き方式）：blocking/high 1件を採用（段にない保存値の Context が Revert / Discard で戻らない）。medium のうち delegate の復元、非数値ポートの dirty 扱い、ディレクトリのトリム、README / Plan の記述を修理として採用。decision required 2件はユーザーが決定：⌘Q 時も確認する、既定ボタンは Keep Editing。
- 再レビュー（`647aefa`）：Decision 2 と採用した medium は resolved。新規 blocking/high 1件：README の「未確定の入力は閉じると破棄」に実装の裏付けがない（focus 喪失時の保存が閉じるときにも走り得る）。correction が新しい blocking を生んだため停止してユーザーに確認 → ユーザーは Requirement を変更：設定ウィンドウは下書き + Apply、未適用で閉じるときは破棄確認、メニューは即時保存のまま。Plan と dig log を更新し、設定画面を再実装して full review を行う。
- 再レビュー（`7dc31f3`）：blocking 解消、新規 blocking/high なし。指摘のうち、`SettingsStoreTests` が実機の `~/Dev/local/Strata` を走査する点と Plan 本文の古い記述を修理として採用。新たな decision required 1件（モデルを一度も選ばないままディレクトリ等を保存すると、暗黙の既定 `model` が永続化され、新ディレクトリに無いモデルになり得る）はユーザー確認待ち。

- [x] **設定モデルの拡張**：`StrataMenubar/Settings/StrataSettings.swift`（`model` 追加、`validate(memory:)`、`MemoryBudget`、`ContextSteps`）、`StrataMenubar/Settings/SettingsStore.swift`（`model` の保存と既定）を変更する。`StrataMenubarTests/StrataSettingsTests.swift`・`SettingsStoreTests.swift` を新しい閾値（物理メモリ 32 GiB 固定で 17 GB 以上と 2 GB 未満が警告、16 GB は警告なし、8192 超・2048 未満の警告は維持）、`model` の既定と往復、`ContextSteps` の index↔値の写像（段にない値は最も近い段）に合わせて更新する。
  - `RunningInfo` の既存テスト（`QuitRequirementTests`、`ServerManagerTests`）は `StrataSettings.default` を使っているので、`model` のメンバーワイズ追加で壊れないことを確認する。
  - 実装：`StrataSettings.model`（既定 `q2_0`、空はエラー）、`validate(memory:)`（2 GB 未満と物理メモリの半分超で警告、文言に GiB と実測を記載）、`MemoryBudget(physicalMemoryBytes:)`（`cacheRange`、`cacheWarningAboveGB = ceil(GiB/2)`）、`ContextSteps.values` と `nearestIndex(to:)`（同距離は小さい段）。`SettingsStore` は `model` キーを保存し、無ければ導入済み一覧から解決（上記）。
  - 検証：testコマンドで53件成功（新規: 物理メモリ基準の警告、model の既定と往復、旧設定の読み込み、ContextSteps）。
- [x] **導入済みモデルの検出と起動計画**：`StrataMenubar/Strata/StrataInstallation.swift`（`installedModels()`、`check(model:)`、Q2_0 専用チェックの廃止）、`StrataMenubar/Strata/AppPaths.swift`（`runConfig(for:)`）、`StrataMenubar/Strata/LaunchPlan.swift`（選んだ tag のベース JSON と run config）、新規 `StrataMenubar/Strata/StrataModelCatalog.swift`（固定一覧と `SetupCommand`）を変更・追加する。`StrataMenubarTests/Support/TestInstallation.swift` を複数の `strata-<tag>.json` を置けるように拡張し、`StrataLaunchPlannerTests.swift` に「選んだ tag の JSON から `strata-<tag>.run.json` を作り `--config` に渡す」「存在しない tag は導入済み一覧を含むエラー」「`.run.json` や `model_name` 欠損 JSON の扱い」、新規テストに「`SetupCommand` が空白と `"` を含むパスを正しく引用する」「カタログの導入済み判定」を追加する。既存の `refusesABaseConfigForAnotherModel` は「別モデルでも導入済みなら起動できる」に置き換える。
  - 既存の `strata-q2_0.run.json` は `strata-q2_0.run.json` のまま（tag が `q2_0` なので名前は変わらない）。
  - 実装：`StrataInstallation.installedModels()`（`strata-*.json` を列挙、`.run.json` は除外、読めない JSON は tag を名前にして残す、tag 順）、`check(model:)`（tag の JSON がなければ導入済み一覧と `setup.sh --setup --model` の案内を含む 1 件）、`configURL(for:)`。`AppPaths.runConfig(for:)`。`StrataLaunchPlanner` は `settings.model` の JSON をベースに `strata-<tag>.run.json` を書いて `--config` に渡す。`StrataModelCatalog.packs`（6 pack、docs/MAC.md と setup.py の数値）、`ModelPack.tag`（小文字化、setup.py の `strata-{tag.lower()}.json` と一致）、`SetupCommand.make`（`~` 展開、`"` と `\` をエスケープ）。
  - 検証：testコマンドで61件成功（新規: 一覧の列挙と並び順、空ディレクトリ、別モデルの起動計画、未導入 tag のエラー文、ファイル欠損、カタログの順序と導入判定、コマンドの引用）。
- [x] **メニューと設定画面**：`StrataMenubar/Views/MenuContent.swift`（Model / Expert cache / Context のサブメニュー、現在の保存値の表示、既存項目は維持）、`StrataMenubar/Views/SettingsView.swift`（スライダー、モデルのポップアップ、即時保存、Save / Revert の廃止、「Stop and Apply」、実測の注記、取得案内のポップアップ・コマンド表示・Copy ボタン、Pi の注記の追記）を変更する。`StrataMenubarApp.swift` は必要なら `AppContainer` の受け渡しだけ変える。
  - 導入済み一覧が空のときは、Model サブメニューに「No strata-<model>.json in <dir>」の無効項目を出し、Start は導入確認のエラーで止まる（既存経路）。
  - メニューのサブメニューと設定画面は同じ `SettingsStore` を見るので、片方で保存すればもう片方にも反映される。
  - 実装：`MenuContent` に「Model: <model_name>」「Expert cache: N GB」「Context: N」のサブメニュー（`Menu` + inline `Picker`、選択で `settingsStore.save`）。導入済み一覧はメニュー内容の評価時に `installedModels()` で取得し、空なら無効の案内行、保存値が一覧になければ「(not installed)」の項目を足す。保存値が選択肢にない数値（4.5 GB や 6144）は現在値の項目として並べる。`SettingsView` の最初の実装（即時保存）は仕様変更で置換（下記）。共通の要素：注記（5 GB → 約 13 GB の実測、警告は実績の説明のみ）、Pi の注記（モデル ID）、「Install another model」セクション（pack の `Picker`、容量・必要メモリ・推奨 RAM・導入済み表示、コマンドの表示と Copy Command（`NSPasteboard.general`）、2 秒間 "Copied" 表示）。
  - 検証：build / test 成功（61件、警告なし）。画面の実機確認は Task 4。
  - 仕様変更後の再実装：`SettingsView` は `draft` を編集し、Apply（`.defaultAction`、dirty かつエラーなしで有効）／Revert、稼働中は「Apply and Restart Server」（保存して `restart`）、下書きが保存値と同じで保存値が実設定と異なるときは「Stop and Apply Saved Settings」。両ボタンは選択中モデルの導入確認失敗時に無効。`WindowCloseGuard`（`NSViewRepresentable`）がウィンドウの delegate を差し替えて `windowShouldClose` で未適用なら `NSAlert` のシート（Discard Changes / Keep Editing）を出し、他の delegate 呼び出しは元の delegate に転送する。メニューからの保存は、下書きが旧保存値と同じときだけ追従。build / test 成功（63件、警告なし）。
  - full review 後の修正：Context スライダーは `draft.maxContext` から導く Binding にして二重状態をなくし、Revert / Discard で段にない保存値も戻る。数値でないポート文字列は dirty 扱い。Apply 時にディレクトリをトリム。`WindowCloseGuard` はビューがウィンドウを離れるとき元の delegate を戻す。ユーザー決定：⌘Q でも未適用の下書きがあれば同じ確認を出し（`SettingsDraftState` を `AppContainer` で共有し `AppDelegate` が先に確認）、ダイアログの既定は Keep Editing（Discard Changes は destructive）。
- [x] **README と実機検証**：`README.md` の Use / Settings / Limitations を更新する（サブメニューでの変更、即時保存、モデル切替と `strata-<model>.json` の一覧、取得コマンドの案内、Q2_0 専用の記述の削除、Pi のモデル ID の注記、警告の根拠）。以下の Final Validation を実施し、結果をこの計画に記録する。
  - 実装：README の冒頭・Requirements・Use（サブメニュー）・Settings（表、警告の根拠、即時保存、`strata-<model>.run.json`）・「Installing another model」・Pi（モデル ID）・Limitations を更新。

## Final Validation

既存のコマンドをそのまま使う（Swift マクロの plugin server はサンドボックス内で動かないため、Herdr ペインで実行する）。

- [x] build：`xcodebuild -project StrataMenubar.xcodeproj -scheme StrataMenubar -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build` → BUILD SUCCEEDED、警告なし（各 Task の test 実行でビルド済み）。
- [x] test：同じ指定で `test` → 全件成功。新規・更新テストで、物理メモリ基準の警告、`model` の既定と保存、`ContextSteps`、導入済み一覧の検出、tag ごとの run config と `--config`、存在しない tag のエラー、`SetupCommand` の引用、カタログの導入済み判定が通る。既存のライフサイクル・実プロセステストは変更なしで通る。→ 最終 HEAD（`8cdef40`）で 63件成功（opt-in の実Strata統合テストは通常実行ではスキップ）、警告なし。
- [x] 実Strata統合テスト：`.build/real-strata.json` を置いて `-only-testing:StrataMenubarTests/RealStrataIntegrationTests` → 既定設定（`model: q2_0`）で従来どおり start → pong → save-only 不変 → restart → stop が通り、run config は `strata-q2_0.run.json`。→ 成功（起動約3秒で loaded、pong、保存のみ不変、4096 で再起動、停止後にプロセスなし、`~/Library/Application Support/StrataMenubar/` には `strata-q2_0.run.json` のみ）。最終 HEAD（`8cdef40`）でも再実行して成功。
- [ ] 実機（GUI）：アプリを起動し、メニューの Model ▸ に `qwen3.8-flash-next-q2_0` が1件、Expert cache ▸ に 1〜32 GB、Context ▸ に 6 段が並び、選ぶと設定画面のスライダーとメニューの表示が一致する。稼働中にメニューから Context を変えると未反映表示と「Stop and Apply Saved Settings」が出て、押すと新しい値で再起動する（`/health` の `max_context` で確認）。設定画面で IQ3_XXS を選んで Copy を押すと、クリップボードに `cd "/Users/ryo.nakae/Dev/local/Strata" && ./setup.sh --setup --model IQ3_XXS --no-start` が入る。cua-driver でステータス項目に到達できない場合は、前回と同様に未検証と明記してユーザー確認へ引き継ぐ。→ **未検証（ユーザー確認へ引き継ぎ）**。前回と同じく cua-driver はステータス項目に到達できず、サブメニュー・スライダー・Copy の画面操作は確認していない。
- [x] `git diff --check` と差分確認 → モデル・ログ・生成設定・ビルド成果物が追跡対象に混入せず、Strata 本体・Pi 設定に変更がない（`strata-q2_0.json` の SHA-256 と `~/Dev/local/.pi/models.json` の mtime が前後で一致）。→ 一致を確認（SHA-256 `38e43c6e…`、models.json の mtime 変化なし）。`git diff --check` は commit 時に確認。

> 各タスクは対応する検証が成功してから完了にする。実装中の軽微な差分と検証結果は該当箇所へ反映し、要件、対象外、公開契約の変更はユーザーへ確認する。最終確認では有効な検証結果を再利用し、計画と実際の変更が一致することを確認する。必要な検証と実装側の必須レビューが通ったら、計画を同名のまま `docs/plans/archived/` へ移す。

## Gate summary

- Review 対象 commit：`60edd37..8cdef40`（bf88ade, 0198f0f, 7a61c7f, 815ecca, 7dc31f3, 647aefa, c8a53f3, 4e1ebd8, 1eac629, c632c8c, 8cdef40）。
- 独立レビュー：全体レビューで blocking 1件（既定モデルの fallback）→ `7dc31f3`。再レビューの新規 blocking（README の「閉じると破棄」に実装の裏付けなし）はユーザーの Requirement 変更（下書き + Apply、閉じるときと ⌘Q で破棄確認、既定は Keep Editing）に置換し `c8a53f3` で再実装 → full review の blocking（段にない Context の Revert）→ `4e1ebd8` → 新規 high（終了経路の discard）→ ユーザー確認の上 `1eac629`・`c632c8c` → 新規 high（Esc で Return の既定が消える）→ ユーザー確認の上 `8cdef40` → 残る指摘なしでクローズ。
- ユーザー決定：未確定入力は破棄（のちに下書き方式へ変更）、導入確認失敗時は「Stop and Apply」無効化、暗黙の既定モデルの永続化は現状維持、⌘Q でも確認、既定ボタンは Keep Editing、終了経路では下書きに触れない、Return を Keep Editing に戻す。
- 未解決の blocking/high・decision required：なし。残した medium/low は completion report に記載。GUI（サブメニュー、スライダー、Apply / Revert、破棄確認シート、⌘Q の確認、Copy Command）は未検証のままユーザー確認へ引き継ぎ。
- Final validation：build / test（63件）成功、実Strata統合テストを最終 HEAD で再実行して成功、`git diff --check` clean、Strata の `strata-q2_0.json` と Pi の `models.json` は無変更、作業ツリーに残置なし。

# Menu Settings and Model Switch Implementation Plan

dig log: [docs/dig/2026-10-15-popover-sliders-model.md](../dig/2026-10-15-popover-sliders-model.md)（決定事項・対象外・撤回済みの正本）

## Requirements

導入済みの Strata モデルの切替と、Expert cache / Context の変更を、メニューバーのメニューと設定画面から行えるようにする。前回の実装（`docs/plans/archived/2026-10-14-strata-menubar.md`）の制約はそのまま守る：Strata 本体・モデル・Pi 設定を書き換えない、自動再起動しない、保存は次回起動に反映し、稼働中は「Stop and Apply」で明示的に適用する。

- メニューは今の SwiftUI `.menu` スタイルのまま。「Model ▸」「Expert cache ▸」「Context ▸」のサブメニューで選択肢を選ぶと保存される。稼働中に保存値が実設定と異なれば、従来どおり未反映表示と「Stop and Apply Saved Settings」を出す。
- Model の選択肢は、Strata ディレクトリ直下にある setup 済みの `strata-<tag>.json` の一覧。設定にはファイル名の stem（`strata-q2_0.json` → `q2_0`）を保存し、表示は JSON の `model_name`。未保存時の既定は `q2_0` があればそれ、なければ一覧の先頭。保存済みの tag の JSON がなくなっていれば、導入済み一覧を添えたエラーにする。Q2_0 専用のチェック（`model_name == qwen3.8-flash-next-q2_0`）は廃止し、選んだ JSON に `model_name`・`exe`・`args`・参照ファイルがあることだけを確認する。
- Expert cache の選択肢は 1 GB 刻み、下限 1 GB、上限は実行中の Mac の物理メモリ量（GiB、32 GiB なら 32）。禁止はせず、物理メモリの 50% 超（32 GiB なら 17 GB 以上）と 2 GB 未満で警告する。文言に根拠（割合、約 0.8 GB で失敗しプロンプト用 1.36 GB が必要という実測）を添える。
- Context の選択肢は 1024 / 2048 / 4096 / 8192 / 16384 / 32768 の 6 段。8192 超（未検証でメモリ増）と 2048 未満（Pi の maxTokens 2048 が入らない）の警告文は維持する。
- 設定画面：Expert cache と Context はスライダー（同じ範囲・段）、Model はポップアップメニュー。保存は即時（スライダーを離した時点、モデルを選んだ時点、ポート・ディレクトリの入力確定時）。検証エラーの値は保存せずエラー表示のままにする。Save / Revert ボタンは廃止し、稼働中に保存値と実設定が異なるときだけ「Stop and Apply」を出す。注記として「この Mac では 5 GB で起動時のフットプリント約 13 GB」の実測を事実として書く。
- 設定画面に、別モデルを取得・導入するための案内を置く：docs/MAC.md の Mac 向け一覧（Q2_0 / IQ3_XXS / IQ3_S / UD-Q4_K_XL / UD-Q5_K_XL / UD-Q6_K_XL、GPU がマップするファイルの容量、必要メモリの目安、推奨 RAM、setup.py のダウンロード容量）をアプリに固定で持ち、ポップアップメニューで選ぶと `cd "<Strataの場所>" && ./setup.sh --setup --model <MODEL> --no-start` が組み上がる。導入済みのものには印を付ける。コマンドはボタンでクリップボードへコピーできる。`--yes` は付けない。
- Pi の注記に「モデルを変えると `/v1/models` のモデル ID（`model_name`）が変わるので `models.json` の `id` も合わせる」を加える。
- 対象外：アプリによるモデルの取得・setup の実行、`.window` スタイルのポップアップ、AppKit でのメニュー作り直し、自動再起動、Strata 本体・モデル・Pi 設定の書き換え。

## Implementation Decisions

- `StrataSettings` に `model: String`（tag）を追加し、`SettingsStore` は UserDefaults に `model` キーを持たない既存ユーザーを既定 `q2_0` として読む。`StrataSettings.default.model == "q2_0"`。既存の `ServerManager` / `RunningInfo.settings` は変更せず、`settings` の等値比較に tag が含まれることで未反映判定が model を含む。
- 物理メモリ依存の値は `MemoryBudget`（`physicalMemoryGiB`、`cacheRange: 1...physicalMemoryGiB`、`cacheWarningAboveGB = physicalMemoryGiB / 2` の切り上げ）として一か所に置き、`ProcessInfo.processInfo.physicalMemory` から作る。`StrataSettings.validate(memory:)` に渡してテストでは固定値を使う。既定引数で現在の Mac を使う。
- Context の段は `ContextSteps.values = [1024, 2048, 4096, 8192, 16384, 32768]` として一か所に置き、スライダーは段の index（0…5）を動かして値へ写す。保存済みの値が段にない場合（旧設定の 6144 など）は、スライダーは最も近い段を示し、保存値は触らない（ユーザーが動かすまで変えない）。
- `StrataInstallation` はルートだけを持ち、`installedModels()` で `strata-*.json` を列挙して `InstalledModel(tag:, modelName:, configURL:)` を返す（`.run.json` は対象外、`model_name` が読めない JSON は `modelName` に stem を入れて一覧に残す）。`check(model tag:)` が選んだ JSON を検証し、tag の JSON がなければ「導入済み: q2_0, ...」を含む 1 件の問題を返す。
- `AppPaths.runConfig(for tag:)` → `strata-<tag>.run.json`。`StrataLaunchPlanner.makePlan` は `settings.model` の JSON をベースに読み、`--config` にその tag の run config を渡す。`RunConfig.make` は変更しない。
- 案内の固定一覧は `StrataModelCatalog`（`name`、`mappedFileGB`、`needsAboutGB`、`recommendedFromGB`、`downloadGB`、`note`）として docs/MAC.md と setup.py の数値を転記する。`SetupCommand.make(strataDirectory:model:) -> String` が `cd "<path>" && ./setup.sh --setup --model <MODEL> --no-start` を返し、パスの `"` と `\` はエスケープする。クリップボードは `NSPasteboard.general` に `clearContents()` 後 `setString(_:forType: .string)`。
- メニューのサブメニューは `Menu { Picker(selection:) { … }.pickerStyle(.inline) }` で作り、選択の `set` で `settingsStore.save` する。`.menu` スタイルではメニューを開くたびに内容が評価されるので、導入済み一覧はメニュー内容の評価時に `installedModels()` を呼んで取得する（ディレクトリ直下の数ファイルの列挙なので同期でよい）。
- 設定画面は `@State` の下書きを廃し、`settingsStore.settings` を元にした Binding で各コントロールを描く。スライダーは `Slider(value:in:step:onEditingChanged:)` で、編集終了時に保存する。ポートとディレクトリは `TextField` の `onSubmit` と focus 喪失で検証し、エラーがなければ保存、あればエラーを表示して保存しない。
- 警告・エラーの文言は `StrataSettings.validate` に集約し、設定画面はそれを表示するだけにする。

## Tasks

Review base commit: `60edd37`。

- [x] **設定モデルの拡張**：`StrataMenubar/Settings/StrataSettings.swift`（`model` 追加、`validate(memory:)`、`MemoryBudget`、`ContextSteps`）、`StrataMenubar/Settings/SettingsStore.swift`（`model` の保存と既定）を変更する。`StrataMenubarTests/StrataSettingsTests.swift`・`SettingsStoreTests.swift` を新しい閾値（物理メモリ 32 GiB 固定で 17 GB 以上と 2 GB 未満が警告、16 GB は警告なし、8192 超・2048 未満の警告は維持）、`model` の既定と往復、`ContextSteps` の index↔値の写像（段にない値は最も近い段）に合わせて更新する。
  - `RunningInfo` の既存テスト（`QuitRequirementTests`、`ServerManagerTests`）は `StrataSettings.default` を使っているので、`model` のメンバーワイズ追加で壊れないことを確認する。
  - 実装：`StrataSettings.model`（既定 `q2_0`、空はエラー）、`validate(memory:)`（2 GB 未満と物理メモリの半分超で警告、文言に GiB と実測を記載）、`MemoryBudget(physicalMemoryBytes:)`（`cacheRange`、`cacheWarningAboveGB = ceil(GiB/2)`）、`ContextSteps.values` と `nearestIndex(to:)`（同距離は小さい段）。`SettingsStore` は `model` キーを保存し、無ければ `q2_0`。
  - 検証：testコマンドで53件成功（新規: 物理メモリ基準の警告、model の既定と往復、旧設定の読み込み、ContextSteps）。
- [x] **導入済みモデルの検出と起動計画**：`StrataMenubar/Strata/StrataInstallation.swift`（`installedModels()`、`check(model:)`、Q2_0 専用チェックの廃止）、`StrataMenubar/Strata/AppPaths.swift`（`runConfig(for:)`）、`StrataMenubar/Strata/LaunchPlan.swift`（選んだ tag のベース JSON と run config）、新規 `StrataMenubar/Strata/StrataModelCatalog.swift`（固定一覧と `SetupCommand`）を変更・追加する。`StrataMenubarTests/Support/TestInstallation.swift` を複数の `strata-<tag>.json` を置けるように拡張し、`StrataLaunchPlannerTests.swift` に「選んだ tag の JSON から `strata-<tag>.run.json` を作り `--config` に渡す」「存在しない tag は導入済み一覧を含むエラー」「`.run.json` や `model_name` 欠損 JSON の扱い」、新規テストに「`SetupCommand` が空白と `"` を含むパスを正しく引用する」「カタログの導入済み判定」を追加する。既存の `refusesABaseConfigForAnotherModel` は「別モデルでも導入済みなら起動できる」に置き換える。
  - 既存の `strata-q2_0.run.json` は `strata-q2_0.run.json` のまま（tag が `q2_0` なので名前は変わらない）。
  - 実装：`StrataInstallation.installedModels()`（`strata-*.json` を列挙、`.run.json` は除外、読めない JSON は tag を名前にして残す、tag 順）、`check(model:)`（tag の JSON がなければ導入済み一覧と `setup.sh --setup --model` の案内を含む 1 件）、`configURL(for:)`。`AppPaths.runConfig(for:)`。`StrataLaunchPlanner` は `settings.model` の JSON をベースに `strata-<tag>.run.json` を書いて `--config` に渡す。`StrataModelCatalog.packs`（6 pack、docs/MAC.md と setup.py の数値）、`ModelPack.tag`（小文字化、setup.py の `strata-{tag.lower()}.json` と一致）、`SetupCommand.make`（`~` 展開、`"` と `\` をエスケープ）。
  - 検証：testコマンドで61件成功（新規: 一覧の列挙と並び順、空ディレクトリ、別モデルの起動計画、未導入 tag のエラー文、ファイル欠損、カタログの順序と導入判定、コマンドの引用）。
- [ ] **メニューと設定画面**：`StrataMenubar/Views/MenuContent.swift`（Model / Expert cache / Context のサブメニュー、現在の保存値の表示、既存項目は維持）、`StrataMenubar/Views/SettingsView.swift`（スライダー、モデルのポップアップ、即時保存、Save / Revert の廃止、「Stop and Apply」、実測の注記、取得案内のポップアップ・コマンド表示・Copy ボタン、Pi の注記の追記）を変更する。`StrataMenubarApp.swift` は必要なら `AppContainer` の受け渡しだけ変える。
  - 導入済み一覧が空のときは、Model サブメニューに「No strata-<model>.json in <dir>」の無効項目を出し、Start は導入確認のエラーで止まる（既存経路）。
  - メニューのサブメニューと設定画面は同じ `SettingsStore` を見るので、片方で保存すればもう片方にも反映される。
- [ ] **README と実機検証**：`README.md` の Use / Settings / Limitations を更新する（サブメニューでの変更、即時保存、モデル切替と `strata-<model>.json` の一覧、取得コマンドの案内、Q2_0 専用の記述の削除、Pi のモデル ID の注記、警告の根拠）。以下の Final Validation を実施し、結果をこの計画に記録する。

## Final Validation

既存のコマンドをそのまま使う（Swift マクロの plugin server はサンドボックス内で動かないため、Herdr ペインで実行する）。

- [ ] build：`xcodebuild -project StrataMenubar.xcodeproj -scheme StrataMenubar -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build` → BUILD SUCCEEDED、警告なし。
- [ ] test：同じ指定で `test` → 全件成功。新規・更新テストで、物理メモリ基準の警告、`model` の既定と保存、`ContextSteps`、導入済み一覧の検出、tag ごとの run config と `--config`、存在しない tag のエラー、`SetupCommand` の引用、カタログの導入済み判定が通る。既存のライフサイクル・実プロセステストは変更なしで通る。
- [ ] 実Strata統合テスト：`.build/real-strata.json` を置いて `-only-testing:StrataMenubarTests/RealStrataIntegrationTests` → 既定設定（`model: q2_0`）で従来どおり start → pong → save-only 不変 → restart → stop が通り、run config は `strata-q2_0.run.json`。
- [ ] 実機（GUI）：アプリを起動し、メニューの Model ▸ に `qwen3.8-flash-next-q2_0` が1件、Expert cache ▸ に 1〜32 GB、Context ▸ に 6 段が並び、選ぶと設定画面のスライダーとメニューの表示が一致する。稼働中にメニューから Context を変えると未反映表示と「Stop and Apply Saved Settings」が出て、押すと新しい値で再起動する（`/health` の `max_context` で確認）。設定画面で IQ3_XXS を選んで Copy を押すと、クリップボードに `cd "/Users/ryo.nakae/Dev/local/Strata" && ./setup.sh --setup --model IQ3_XXS --no-start` が入る。cua-driver でステータス項目に到達できない場合は、前回と同様に未検証と明記してユーザー確認へ引き継ぐ。
- [ ] `git diff --check` と差分確認 → モデル・ログ・生成設定・ビルド成果物が追跡対象に混入せず、Strata 本体・Pi 設定に変更がない（`strata-q2_0.json` の SHA-256 と `~/Dev/local/.pi/models.json` の mtime が前後で一致）。

> 各タスクは対応する検証が成功してから完了にする。実装中の軽微な差分と検証結果は該当箇所へ反映し、要件、対象外、公開契約の変更はユーザーへ確認する。最終確認では有効な検証結果を再利用し、計画と実際の変更が一致することを確認する。必要な検証と実装側の必須レビューが通ったら、計画を同名のまま `docs/plans/archived/` へ移す。

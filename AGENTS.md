# AGENTS.md

macOS menu bar app (Swift 6, SwiftUI, macOS 15+, no dependencies) that starts, stops and configures a
locally installed Strata LLM server. `README.md` describes the behaviour users see; this file is for
working on the code. `CLAUDE.md` is a symlink to this file.

## Commands

Build and test with xcodebuild only; there is no package manager or script layer.

```sh
xcodebuild -project StrataMenubar.xcodeproj -scheme StrataMenubar -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project StrataMenubar.xcodeproj -scheme StrataMenubar -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
open .build/DerivedData/Build/Products/Debug/StrataMenubar.app
```

- Swift macros (`@Observable`, `@Test`, `#expect`) need the compiler's plugin server, which runs its own
  `sandbox-exec`. Inside a sandbox that forbids nested sandboxing the build fails with
  `swift-plugin-server produced malformed response`; run xcodebuild outside it.
- `-only-testing:StrataMenubarTests/<Suite>` narrows a test run. Add `.build/real-strata.json` (`{}`,
  or `{"strataDirectory": "/path/to/Strata"}`) to enable `RealStrataIntegrationTests`, which starts the
  real server through the app's own components; remove the file afterwards.
- Nothing is linted or formatted automatically; the compiler must stay warning-free.

## Validation before a commit

1. `build` and `test` succeed with no compiler warnings.
2. After touching `StrataMenubar/Strata/`: run `RealStrataIntegrationTests` once against a real
   checkout and confirm `pgrep -f serve/server.py` is empty afterwards; also download, cancel, resume and delete
   a pack once in the running app and confirm `pgrep -f setup_mac.py` is empty afterwards.
3. `git diff --check` is clean; no logs, run configs, models or `.build/` output are tracked.

## Release

Bump `MARKETING_VERSION` in `project.pbxproj`, commit, then push a `vX.Y.Z` tag.
`.github/workflows/release.yml` tests, builds with Developer ID signing and the hardened runtime (passed on
the command line, so the project itself stays ad-hoc signed), notarizes and staples the DMG, and creates a
draft release. Publishing the draft runs `update-homebrew-cask.yml`, which points
`ryonakae/homebrew-tap`'s `Casks/strata-menubar.rb` at the new DMG. Signing secrets live in the `release`
environment, which only `v*` tags can use.

## Layout

- `StrataMenubar/App/`: `StrataMenubarApp` (MenuBarExtra + Settings scene), `AppDelegate` (quit
  confirmation), `AppContainer` (wires the real dependencies once).
- `StrataMenubar/Settings/`: `StrataSettings` (values, validation, `MemoryBudget`, the step lists),
  `EngineDefaults` (what the engine picks when a value is unset, computed for display), `SettingsStore` (UserDefaults).
- `StrataMenubar/Strata/`: everything that touches Strata. `StrataInstallation` (installed
  `strata-<tag>.json`, checks), `StrataDataDirectory` (setup's data directory, the state of a pack's files),
  `ModelLibrary` (installed and downloaded models, kept current by `DirectoryWatcher`; `ExternalSetup` spots a setup
  run from a terminal), `ModelInstaller` (runs Strata's setup as an owned process and follows its log through
  `SetupOutput`), `ModelFiles` (what a deletion moves to the Trash), `RunConfig` + `LaunchPlan` (run config and
  spawn plan), `PosixProcessLauncher`
  (posix_spawn in a new process group), `HealthProbe`, `ServerManager` (the state machine), `StrataModelCatalog`.
- `StrataMenubar/Views/`: `MenuContent` (the menu), `SettingsView` (draft + Apply, the Models section),
  `PackStatus+Display` (a pack row's state and why Download cannot run), `SettingsSummary` (the saved values as the
  menu lists them), `WindowCloseGuard`.
- `StrataMenubar/Assets.xcassets`: the menu bar icon (Font Awesome `layer-group`) as two template SVGs, full and half opacity (`LayerGroup`, `LayerGroupDimmed`);
  `ServerState+Display` picks one by state.
- `StrataMenubarTests/`: Swift Testing suites; `Support/Fakes.swift` (fake launcher, process, probe,
  planner, preparer) and `Support/TestInstallation.swift` (a throwaway Strata layout and data directory on disk).
- `docs/plans/archived/`: implementation plans with the decisions and validation records.
  `docs/dig/`: the question-and-answer logs behind them. Read these before changing a decision.
- The Xcode project uses synchronized folders: a new file under `StrataMenubar/` or
  `StrataMenubarTests/` is picked up without editing `project.pbxproj`.

## Invariants

These are the contract with the user; a change needs a new plan, not a quiet edit.

- The app itself never writes into the Strata checkout, its model files or any client's configuration.
  What changes there is written by the Strata setup the user asked for and by a deletion the user confirmed,
  which moves files to the Trash. The run config goes to `~/Library/Application Support/StrataMenubar/`, logs to
  `~/Library/Logs/StrataMenubar/`.
- The app runs Strata's setup only as `setup.py --setup --model <MODEL> --no-start --vision no`, for a
  download or a first-start preparation, one at a time. Its own setup never prepares beside a loaded engine: a
  download is stopped at setup's step 6 while a server is up, and Start is unavailable while it prepares. A
  setup started outside the app only keeps its pack from being downloaded or deleted here.
- Signal only the process groups the app spawned (the server's and setup's). A Strata server or setup it did
  not start is shown as such and never signalled; a stop that fails keeps ownership and blocks a restart.
- The server listens on `127.0.0.1` only.
- Saved settings apply at the next start. Nothing restarts the server except the explicit
  "Stop and Apply" / "Apply and Restart" actions; settings change only in the settings window via Apply, the menu lists them.
- No automatic restart loops, no adoption of leftover processes, no installing or updating Strata itself.

## Conventions

- Swift 6 language mode with strict concurrency: UI and `ServerManager` are `@MainActor`; anything
  crossing threads is `Sendable` or `@unchecked Sendable` with a lock.
- Keep the design testable through the existing seams: `ProcessLaunching`, `HealthProbing`,
  `LaunchPlanning`, `ModelPreparing`. Lifecycle behaviour is tested with the fakes; process ownership with real
  `/bin/sh` fixtures in `PosixProcessLauncherTests`, `ModelInstallerTests` and `ModelLibraryTests`.
- Views have no unit tests; verify UI changes by running the app.
- Comments explain why, not what. Comments, docs and commits are English. Commit messages follow
  Conventional Commits (`feat:`, `fix:`, `docs:`, ...); never amend, rebase or force-push shared history.
- Keep `README.md` user-facing (behaviour, settings, limitations) and this file agent-facing.

# Sparkle updates and settings window layout (v0.2.0) Implementation Plan

Decisions: [docs/dig/2026-10-17-sparkle-updates.md](../dig/2026-10-17-sparkle-updates.md),
[docs/dig/2026-10-17-settings-window-layout.md](../dig/2026-10-17-settings-window-layout.md).

## Requirements

- Manual updates through Sparkle 2.10.0 (SPM): "Check for Updates…" in the menu, just above "Settings…", and
  on the Version row at the bottom of the settings window. The button is disabled while Sparkle cannot check.
  No automatic checks or downloads, and no permission prompt.
- "Install and Relaunch" goes through the existing `AppDelegate.applicationShouldTerminate`: a server or setup
  the app started is stopped only after "Stop and Quit". If the quit is cancelled or the stop fails, the
  update is installed at a later quit (Sparkle's standard behaviour). The server is never restarted
  automatically after an update.
- The update archive is the notarized `StrataMenubar_<version>_arm64.dmg`. CI EdDSA-signs it and attaches an
  `appcast.xml` to the draft release. The feed is
  `https://github.com/ryonakae/strata-menubar/releases/latest/download/appcast.xml`, so an update is offered
  only once the draft is published. The release notes are `sparkle:fullReleaseNotesLink` →
  `https://github.com/ryonakae/strata-menubar/releases/tag/v<version>`.
- The EdDSA key lives in the user's login keychain, in the `release` environment secret
  `SPARKLE_ED_PRIVATE_KEY` and in a password manager. The public key is `SUPublicEDKey`.
- The Homebrew cask does not get `auto_updates true`. `update-homebrew-cask.yml` stays as it is.
- The Models picker uses the `StrataModelCatalog.packs` order, the same as the pack rows. Installed and
  downloaded packs are interleaved at their catalog position, then installed models outside the catalog by
  tag, then the selected model when it is neither installed nor downloaded.
- The settings window can be resized in both directions: minimum 560 pt wide and about 480 pt high, no
  maximum, and the same initial size as today.
- A bar pinned to the bottom of the settings window holds the validation messages and Revert / Apply and
  Restart Server / Apply. The footnote ("Applied settings are used at the next start…") and "Stop and
  Apply Saved Settings" stay where they are.
- Added after the first run of the app (dig Q11–Q14):
  - The window really resizes. The `Settings` window's NSWindow is not resizable by default, which the
    first implementation missed.
  - Validation messages appear inside the section of the setting they concern. The bottom bar shows only one
    line, and only while there are errors (the count, and that fixing them enables Apply). Warnings never
    appear in the bar. The engine's MTP note is not shown twice. This replaces "validation messages in the
    bar" above, and the three buttons stay in the bar.
  - The Strata directory is shown read-only, with "Choose…" opening a Finder folder panel. The chosen
    path is a draft until Apply. There is no "Show in Finder".
  - Section order: Running server → Strata installation → Models → Memory and context → Engine → Server →
    the footnote → About.
  - A titled "About" section holds the version with "Check for Updates…", "Made by Ryo Nakae" (no link), a
    link to https://github.com/ryonakae/strata-menubar and "MIT License". There are no credits in the app.
    The menu item stays.
- The release is v0.2.0. It includes the unpushed app icon and version display commits (0d69748, 7af3703).
  Its notes tell v0.1.x users to update by hand once.
- Out of scope: automatic checks and downloads, stopping processes without asking for an update, restarting
  the server after an update, and `auto_updates` in the cask.
- The AGENTS.md invariants are unchanged. "No dependencies" becomes "Sparkle is the only dependency; adding
  another needs a plan".

## Implementation Decisions

- **Build number (proposal, not part of the dig):** Sparkle compares only `CFBundleVersion`, and it is
  `1` in every release so far, so no update would ever be offered. From v0.2.0 on, `CURRENT_PROJECT_VERSION`
  equals `MARKETING_VERSION` (`0.2.0`), and the release workflow fails unless both match the tag. Sparkle's
  comparator splits on character type, so whatever scheme ships first is effectively permanent. A dotted
  version keeps it monotonic with the tags. The settings window then shows only the version, plus the build in
  parentheses only when it differs.
- **Info.plist keys:** `SUFeedURL`, `SUPublicEDKey` and `SUEnableAutomaticChecks = NO` go in a partial plist
  merged through `INFOPLIST_FILE` (with `GENERATE_INFOPLIST_FILE` still YES). The plist sits outside the
  synchronized folders, at `Config/StrataMenubar-Info.plist`. Under `StrataMenubar/` it would be copied as a
  resource and clash with the generated Info.plist. `INFOPLIST_KEY_*` cannot carry these keys.
  `SUEnableAutomaticChecks = NO` also suppresses Sparkle's permission prompt.
- **Updater object:** a `@MainActor @Observable` `AppUpdater` in `StrataMenubar/App/`, owned by `AppContainer`.
  It wraps `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)`,
  mirrors `canCheckForUpdates` through KVO onto the main actor, and exposes `checkForUpdates()`. The Sparkle
  types are MainActor-annotated in 2.9+. No new seam or delegate is needed, because Sparkle already
  delivers its quit request as an Apple quit event that `applicationShouldTerminate` can delay or cancel.
  The tests run inside the app, so the updater also starts there. With automatic checks off it does no network
  access and shows no prompt, but it fails with an alert unless `SUPublicEDKey` is present. That makes the key
  a prerequisite for building.
- **Nested Sparkle code in CI:** `xcodebuild build` re-signs `Sparkle.framework` but leaves its helpers
  ad-hoc signed. Notarization needs Developer ID on every nested executable. Sparkle also skips its atomic swap
  when Autoupdate's team differs from the app's. After the build, CI deletes
  `Sparkle.framework/Versions/B/XPCServices` and the `XPCServices` symlink, because a non-sandboxed app does not
  use them. It then re-signs, from the inside out, `Versions/B/Autoupdate`, `Versions/B/Updater.app`, the
  framework and finally the app, each with `-f -s "$APPLE_SIGNING_IDENTITY" -o runtime --timestamp`. It never
  uses `--deep` and passes no entitlements, so `get-task-allow` stays out. A strict deep verify follows.
- **Appcast:** `generate_appcast` from the SPM artifacts
  (`$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/`), not hand-written XML. It reads
  `CFBundleVersion`, the short version and `LSMinimumSystemVersion` from the bundle. It runs on a directory
  that holds only the stapled DMG, with the key piped in through `--ed-key-file -`,
  `--download-url-prefix https://github.com/ryonakae/strata-menubar/releases/download/v${VERSION}/` and
  `--full-release-notes-url` set to the release page, and `--link` set to the repository. Because the directory starts empty, the appcast lists only
  this version, which is enough for a feed that always points at the latest release.
- **Issue placement:** `SettingsIssue` gains the section it belongs to. `StrataSettings.validate` assigns it, the
  view filters by section, and `StrataSettingsTests` checks the assignment. The view's own "port must be a
  number" error belongs to Server. For MTP, the Engine section keeps its footnote only while the verify
  window is "As set up". When a window is set, the validation warning says the same thing.
- **Resizing:** a small `NSViewRepresentable` in `StrataMenubar/Views/` adds `.resizable` to its window's
  `styleMask` once it is in a window. It lives next to `WindowCloseGuard`, which only guards closing.
- **Model choices:** a pure `static` function in `ModelLibrary` builds the ordered picker entries from
  `installed`, `packs` and the selected tag. `SettingsView` only renders it, which keeps the ordering in the
  tested layer.
- **Window:** `.frame(minWidth: 560, idealWidth: 560, minHeight: 480)` on the form and
  `.windowResizability(.contentMinSize)` on the `Settings` scene. The bottom bar is a
  `.safeAreaInset(edge: .bottom)` with a bar background. The initial size has to be checked by running the
  app, because the modifiers do not guarantee it.

## Tasks

Review base: `a18f285` (the commits after it, including 0d69748 and 7af3703, belong to this plan).


- [x] Sparkle package: add `https://github.com/sparkle-project/Sparkle`, exactly 2.10.0, product `Sparkle`, to
  the app target in `StrataMenubar.xcodeproj/project.pbxproj`, and commit
  `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. `.gitignore` only ignores `xcuserdata/`.
  - Do this before the key task: `generate_keys` comes from the package artifacts.
- [x] EdDSA key (the user runs these; the private key is never shown to the agent):
  1. Run `generate_keys` from `.build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/` to create the
     key and print the public key.
  2. Export it with `generate_keys -x <file>`.
  3. Pipe the file into `gh secret set SPARKLE_ED_PRIVATE_KEY -R ryonakae/strata-menubar --env release`.
  4. Store the same contents in the password manager.
  5. Delete the file.

  The agent records the public key, which `generate_keys -p` prints.
- [x] Updater wiring: `Config/StrataMenubar-Info.plist` holds the three keys. Both app configurations in
  `project.pbxproj` get `INFOPLIST_FILE`, and `CURRENT_PROJECT_VERSION` is set to `0.2.0` alongside
  `MARKETING_VERSION = 0.2.0` (app and test targets). Add `StrataMenubar/App/AppUpdater.swift` and hand it
  through `AppContainer` and `StrataMenubarApp` to `MenuContent` and `SettingsView`. The menu item goes just
  above "Settings…", and the settings window gets a button on the Version row in `aboutSection`, with the
  version display adjusted as decided above.
  - Done: public key `HG/sTCjyXdsv7DBwcmkILl7Ezro0ND4LeckmBm2f9To=`; the built Info.plist carries the three keys and
    `0.2.0` / `0.2.0`; build and the full test run (110 tests) pass without compiler warnings.
- [x] Release pipeline: change `.github/workflows/release.yml`.
  - "Validate release version" also requires `CURRENT_PROJECT_VERSION` to equal the tag.
  - A new step between "Build signed app" and "Build DMG" removes the XPC services and re-signs the nested
    code as decided above.
  - After notarization, a step runs `generate_appcast` with `SPARKLE_ED_PRIVATE_KEY`. That secret is checked
    with the others in "Prepare Apple signing credentials".
  - `appcast.xml` joins the DMG and the checksum in both `gh release create` and `gh release upload`.
  - Done: actionlint passes; the workflow itself is validated by the v0.2.0 run (Final Validation).
- [x] Model picker order: add the ordering function to `StrataMenubar/Strata/ModelLibrary.swift`, use it in the
  `modelsSection` picker of `StrataMenubar/Views/SettingsView.swift`, and cover it in
  `StrataMenubarTests/ModelLibraryTests.swift`. The tests cover installed and downloaded packs interleaved in
  catalog order, a non-catalog installed model after them, and an unknown selection last and only when unknown.
  - Done: `ModelLibrary.ModelChoice` and `ModelLibrary.choices(installed:packs:selected:)`; the new test failed
    first (no member `choices`) and passes with the `ModelLibraryTests` suite (6 tests).
- [x] Settings window layout: in `StrataMenubar/Views/SettingsView.swift`, add the minimum and ideal frame and
  move the issues and the three buttons into the bottom inset bar, leaving the footnote in the form. In
  `StrataMenubar/App/StrataMenubarApp.swift`, set the `Settings` scene's resizability.
  - Done: `actionBar` pinned with `.safeAreaInset(edge: .bottom)`; builds without warnings. The window checks in
    Final Validation are still to be done in the running app.
- [x] Settings window follow-ups (dig Q11–Q14):
  - Add the section to `SettingsIssue` in `StrataMenubar/Settings/StrataSettings.swift`, with tests in
    `StrataMenubarTests/StrataSettingsTests.swift`.
  - In `StrataMenubar/Views/SettingsView.swift`:
    - show each section's issues inside that section, and put the error line in the bar
    - add the read-only directory with "Choose…" (`NSOpenPanel`, folders only, starting at the current
      directory)
    - reorder the sections and make the titled About section
    - attach the resizable-window helper (new file in `StrataMenubar/Views/`)
  - Update README's Settings section to match.
  - Done: `SettingsIssue.Section`; the new test failed first (no member `section`); the full suite (111 tests)
    passes without compiler warnings. In the running app SwiftUI removed the added `.resizable` style again, so
    the helper now restores it whenever it is removed; the window gets a default size of 560 × 720, and About drops
    the license row (it stays in README's Credits). The checks in the running app passed.
- [x] Docs:
  - `AGENTS.md`:
    - Change the "no dependencies" claim in the header and "there is no package manager" in Commands
      (SPM resolves Sparkle on the first build).
    - In Release, add the build number rule, the nested re-signing, the appcast and the draft-to-publish
      timing of updates.
    - In Layout, add `AppUpdater` and `Config/StrataMenubar-Info.plist`.
    - Add a Conventions line saying that Sparkle is the only dependency.
  - `README.md`:
    - Install: updates through Check for Updates, and v0.1.x must be updated by hand once.
    - Use: the menu item.
    - Settings: a resizable window and the pinned bar.
    - Models: the picker order.
    - Limitations: checks are manual only.
    - Credits: Sparkle, MIT.
  - Done in 91c990d and d8de3ba (README promises a relaunch only for Install and Relaunch, after a review
    `decision required` resolved as option A).
- [ ] Release v0.2.0, after Final Validation passes locally:
  1. Push main, then tag `v0.2.0`.
  2. Inspect the draft's assets and `appcast.xml`.
  3. Write the release notes, including the one-time manual update for v0.1.x.
  4. Publish after the user confirms.
  5. Confirm that the tap moved to 0.2.0.
  6. Run the end-to-end update check below.

## Final Validation

- [x] Build and tests: the AGENTS.md `build` and `test` commands, outside the sandbox (herdr pane) → both succeed
  with no compiler warnings, and no Sparkle alert appears during the test run.
- [x] Model order: `-only-testing:StrataMenubarTests/ModelLibraryTests` → the new cases pass. This also runs in
  the full test run above.
- [x] Updater in a local build: open the Debug app → no permission prompt at launch. "Check for Updates…" is
  enabled in the menu and in settings. Before v0.2.0 is published it reports an error or "no update", without
  crashing.
- [x] Issue sections: `-only-testing:StrataMenubarTests/StrataSettingsTests` → each error and warning carries the
  section of its setting.
- [x] Settings window follow-ups in the app:
  - an invalid port shows its error in Server, and the bar shows one error line
  - a 5-token verify window shows its warning in Engine and nothing in the bar
  - "Choose…" sets the directory and the installation check reruns
  - the sections are in the agreed order, and About has its four items with a working GitHub link
- [x] Settings window: the first opening has the same size as before. It resizes down to 560 × about 480 and up
  freely, the layout holds at the minimum, and the bottom bar stays visible while scrolling. At the minimum height the
  footnote and the Version row can still be scrolled fully above the bar. Its messages and
  buttons enable and disable as before: dirty, errors, and running with differing settings.
- [x] Picker order in the app: with at least two installed packs whose tag order differs from the catalog order
  (for example IQ3_S and Q2_0), the picker and the rows list them in the same order.
- [ ] CI release: the run for `v0.2.0` succeeds. Notarization says `Accepted` with the Sparkle helpers
  inside. The draft has the DMG, `.sha256` and `appcast.xml`. In `appcast.xml`:
  - `sparkle:version` is `0.2.0`
  - `sparkle:minimumSystemVersion` is 15.0
  - the enclosure URL is `…/releases/download/v0.2.0/StrataMenubar_0.2.0_arm64.dmg` (not `latest`)
  - `sparkle:edSignature` is present
  - `sparkle:fullReleaseNotesLink` is the tag page

  On the downloaded DMG, `stapler validate` and `spctl -a -t open --context context:primary-signature` →
  accepted. `codesign -dv` on Autoupdate and Updater.app inside the app → `Authority=Developer ID Application:
  Ryo Nakae (ELFWBE4NMA)`, with the runtime flag set.
- [ ] End-to-end update, after publishing: build the Debug app locally with
  `CURRENT_PROJECT_VERSION=0.1.99 MARKETING_VERSION=0.1.99` on the xcodebuild command line, and start a
  Strata server from it.
  - "Check for Updates…" offers 0.2.0, which also proves that the `releases/latest/download` redirect is
    followed. "Release Notes" opens the tag page.
  - "Install and Relaunch" shows "Stop and Quit". Cancelling leaves the app and the server running.
  - Accepting stops the server, replaces the app and relaunches it as 0.2.0. `pgrep -f serve/server.py` is
    empty afterwards, and the server is not running in the relaunched app.

  Do this in a scratch copy of the app outside `/Applications`, so the installed copy is not touched.
- [x] Repository hygiene: `git diff --check` is clean, and no `.build/`, keys or exported key files are tracked
  (`git status --short` and `git ls-files | grep -i -E 'key|\.p8|\.p12'` show nothing unexpected).

> 各タスクは対応する検証が成功してから完了にする。実装中の軽微な差分と検証結果は該当箇所へ反映し、要件、対象外、公開契約の変更はユーザーへ確認する。最終確認では有効な検証結果を再利用し、計画と実際の変更が一致することを確認する。必要な検証と実装側の必須レビューが通ったら、計画を同名のまま `docs/plans/archived/` へ移す。

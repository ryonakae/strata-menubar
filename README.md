# strata-menubar

A small macOS menu bar app that starts and stops a locally installed
[Strata](https://github.com/Niko1221/Strata) server running Qwen3.8-Flash-Next,
lets you pick which installed model to run, and changes its memory-related
settings. It replaces the terminal pane you would otherwise keep open for
`run-<model>.sh`; once the server is up, clients such as
[Pi](https://github.com/badlogic/pi-mono) use it as before.

The app does not install, update or edit Strata or its model files. It needs a
finished Strata setup and starts whichever `strata-<model>.json` setup wrote.

## Requirements

- macOS 15 or newer on Apple Silicon
- Xcode 16 or newer to build (Xcode 27 was used)
- A working Strata checkout with at least one model set up by `setup.sh`, by
  default at `~/Dev/local/Strata`, containing `.venv/bin/python`,
  `serve/server.py` and a `strata-<model>.json` (for example `strata-q2_0.json`)

## Build

```sh
xcodebuild -project StrataMenubar.xcodeproj -scheme StrataMenubar -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The app lands in `.build/DerivedData/Build/Products/Debug/StrataMenubar.app`.
No Apple developer account is needed; the binary is ad-hoc signed. Start it from
Finder or with `open .build/DerivedData/Build/Products/Debug/StrataMenubar.app`.
It shows an icon in the menu bar and nothing in the Dock.

Run the unit tests with the same command and `test` instead of `build`.

One test, `RealStrataIntegrationTests`, drives the real Strata installation
through the app's own components (start, answer, restart with a smaller
context, stop). It is skipped unless `.build/real-strata.json` exists; create
that file (`{}` is enough, or `{"continueDir": "/some/dir"}` to have the test
pause while the server is up) to run it. It loads the model, writes the app's
real run config and logs under `~/Library`, and takes a few minutes. If it
fails before its final stop it tries to stop the server it started; check the
menu bar app or `pgrep -f serve/server.py` afterwards.

## Use

The menu shows one of these states:

| State | Meaning |
| --- | --- |
| Stopped | No Strata server is known on the configured port. The app only looks for Strata; another service holding the port is reported when you press Start. |
| Starting | The server this app started is loading the model. |
| Running | `/health` reports the model as loaded; the line shows model, context and port. |
| Stopping | The server and its engine are shutting down. |
| External Strata | A Strata server somebody else started is listening on the port. The app never stops it. |
| Error | A launch or a stop failed, the server exited on its own, or the port is held by something that is not Strata; the message says what to look at. A failing health check of a running server is shown on the Running line instead. |

Actions:

- **Model**, **Expert cache** and **Context** are submenus of the saved
  settings. Picking a value saves it at once; it applies at the next start. A
  running server keeps the values it was started with until you choose **Stop
  and Apply Saved Settings**. The Model submenu lists the `strata-<model>.json`
  files in the Strata directory by their model name.
- **Start Server** starts `serve/server.py` with the saved settings, bound to
  `127.0.0.1` only. The server and the Metal engine it spawns run in their own
  process group owned by the app.
- **Stop Server** sends SIGTERM to the server so it can shut the engine down
  itself, waits for that, and then terminates (and if necessary kills)
  whatever is left in the group. Stopping can take up to about two minutes
  (90 s for the server to close the engine itself, then 20 s and 10 s for
  anything left); the engine frees its memory first.
- **Stop and Apply Saved Settings** appears when the saved settings differ from
  the ones the running server was started with.
- **Open Chat** opens Strata's web page of the server that is actually
  listening (its own port, not a newly saved one).
- **Open Server Log** / **Open Engine Log** / **Show Logs in Finder** open the
  files under `~/Library/Logs/StrataMenubar/`. `server.log` is the Python
  server's stdout and stderr; `engine.log` is what the engine writes. A file
  over 10 MB is moved to `.1` at the next start.
- **Quit** asks for confirmation while a server the app started is running or
  starting, stops it first, and keeps the app open if you cancel. A server the
  app did not start is left alone.

## Settings

Open **Settings…** from the menu (or ⌘,). The window edits a draft: change
the sliders, the model picker or the text fields, then press **Apply** to save
(it is disabled while a value is invalid) or **Revert** to go back to the
saved values. Closing the window or quitting the app with unapplied changes
asks whether to discard them (Keep Editing is the default answer). The menu
bar's submenus, by contrast, save at once.

| Setting | Default | Notes |
| --- | --- | --- |
| Strata directory | `~/Dev/local/Strata` | Must contain a finished setup. The window lists what is missing. |
| Model | `q2_0`, else the first installed | One of the `strata-<model>.json` files in the Strata directory. |
| Expert cache (GB) | 5 | `STRATA_METAL_ARENA_GB`, in decimal GB. Slider from 1 GB to the Mac's physical memory in 1 GB steps. |
| Context (tokens) | 8192 | `--max-context` for the engine. Slider over 1024, 2048, 4096, 8192, 16384 and 32768. |
| Port | 8080 | Must be between 1024 and 65535; an invalid entry keeps the previous value. |

The expert cache is only the arena the engine keeps the most-used experts in.
It is not a limit on Strata's total memory: with a 5 GB cache the engine's
footprint was about 13 GB after start on an M-series Mac with 32 GiB. A fixed
value is never shrunk automatically when memory runs short, and "about 16 GB
overall" is an operating goal, not something the app enforces. Any value in
the slider's range is accepted; the app only warns, with the reason, for caches
under 2 GB (the engine needs about 1.36 GB of the arena for a prompt's buffers
and failed at about 0.8 GB) or over half of the Mac's memory, and for contexts
over 8192 (untested here, more memory) or under 2048 (Pi's maxTokens does not
fit).

Settings are saved in the app's user defaults and apply at the next start.
While a server is running, the window shows the settings it was started with.
**Apply and Restart Server** saves the draft and restarts with it; when the
draft is applied but the saved settings differ from the running ones, **Stop
and Apply Saved Settings** restarts with the saved values. Both buttons (and the menu's) are
disabled while the selected model's installation check fails, so a working
server is not stopped for a launch that cannot succeed. The app never restarts
the server on its own.

At each start the app reads the selected model's `strata-<model>.json` from the
Strata directory and writes a copy with only the managed keys changed
(`--max-context`, `STRATA_METAL_ARENA_GB`, `STRATA_METAL_STREAM=1` when the
base has no such key, the engine log path and the port) to
`~/Library/Application Support/StrataMenubar/strata-<model>.run.json`. The
original file, `run-<model>.sh` and the model files are never modified.

### Installing another model

The window's "Install another model" section lists the packs Strata's Mac
documentation describes (Q2_0, IQ3_XXS, IQ3_S, UD-Q4_K_XL, UD-Q5_K_XL,
UD-Q6_K_XL) with their download size, the file the GPU maps, the memory they
need and the recommended RAM, and marks the ones already installed. Pick one
and press **Copy Command** to get

```sh
cd "/path/to/Strata" && ./setup.sh --setup --model IQ3_XXS --no-start
```

Run it in a terminal yourself: setup downloads and prepares the model and
writes `strata-<model>.json`; `--no-start` keeps it from starting a server of
its own. The new model then appears in the Model menu. The app never runs
setup.

### Pi

Pi reads this server through its `strata` provider entry in
`~/Dev/local/.pi/models.json` (`http://127.0.0.1:8080/v1`, `contextWindow`
8192, `maxTokens` 2048, model id `qwen3.8-flash-next-q2_0`). After changing
the port, the context or the model here, edit that file by hand; the model id
must equal the server's model name (what `/v1/models` reports). The app does
not touch Pi's configuration.

With the 8192 context, Pi's default coding system prompt plus its built-in
tools did not fit: the server answered 400 because the prompt alone was 8,326
tokens. A short question worked with tools off and a small system prompt, for
example:

```sh
pi -p --no-tools --system-prompt "You are a terse assistant." \
  --provider strata --model qwen3.8-flash-next-q2_0 "Reply with the single word: pong"
```

If your Pi configuration lives outside the default `~/.pi/agent`, point
`PI_CODING_AGENT_DIR` at it first (here: `~/Dev/local/.pi`).

## Limitations

- Only models that Strata's setup has already installed; image input, the MTP
  draft and every other engine option stay as the model's base config has them.
- No login item, launchd service, LAN access, authentication, signing or
  notarisation.
- A server left over from an app crash is shown as "External Strata" and is not
  adopted; stop it yourself before starting a new one.

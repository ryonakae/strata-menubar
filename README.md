# strata-menubar

A small macOS menu bar app that starts and stops a locally installed
[Strata](https://github.com/Niko1221/Strata) server running Qwen3.8-Flash-Next,
lets you pick which installed model to run, and changes its memory, idle-unload
and engine settings. It replaces the terminal pane you would otherwise keep open for
`run-<model>.sh`; once the server is up, clients use it as before.

The app does not install, update or edit Strata or its model files. It needs a
finished Strata setup and starts whichever `strata-<model>.json` setup wrote.

## Requirements

- macOS 15 or newer on Apple Silicon
- Xcode 16 or newer to build (Xcode 27 was used)
- A working Strata checkout with at least one model set up by `setup.sh`, by
  default at `~/Strata`, containing `.venv/bin/python`,
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

Tests, project layout and the rules for changing the code are in
[AGENTS.md](AGENTS.md).

## Use

The menu shows one of these states:

| State | Meaning |
| --- | --- |
| Stopped | No Strata server is known on the configured port. The app only looks for Strata; another service holding the port is reported when you press Start. |
| Starting | The server this app started is loading the model. |
| Running | `/health` reports the model as loaded; the line shows model, context and port. On a server started with idle unload, an unloaded model is shown as "(model unloaded after idle; loads on the next request)" with a moon icon, because the server does not say whether it is idle or loading again. |
| Stopping | The server and its engine are shutting down. |
| External Strata | A Strata server somebody else started is listening on the port. The app never stops it. |
| Error | A launch or a stop failed, the server exited on its own, or the port is held by something that is not Strata; the message says what to look at. A failing health check of a running server is shown on the Running line instead. |

Actions:

- **Settings for the next start** lists the saved values read-only: model,
  expert cache (Auto or a fixed size), context, port and idle unload always; the
  kept memory, verify window, prompt chunk and fit max_tokens only when they are
  not left to the engine or to setup. A row whose value differs from the running
  server's adds "(running: …)". Any row opens the settings window; the menu
  itself changes nothing. A running server keeps the values it was started with
  until you choose **Stop and Apply Saved Settings**.
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
bar only lists the saved values.

| Setting | Default | Notes |
| --- | --- | --- |
| Strata directory | `~/Strata` | Must contain a finished setup. The window lists what is missing. |
| Model | `q2_0`, else the first installed | One of the `strata-<model>.json` files in the Strata directory. |
| Expert cache | Auto | With the toggle on, the engine sizes the expert arena itself and `STRATA_METAL_ARENA_GB` is not written. With it off, the slider sets a fixed size in decimal GB, from 1 GB to the Mac's physical memory in 1 GB steps (5 GB when first switched). A cache saved by an earlier version of this app stays fixed. |
| Keep free for macOS | Engine default | `STRATA_METAL_KEEP_FREE_GB`, only with an automatic cache: what the engine leaves to macOS while it sizes the arena. The engine's own rule is 7 GB or 15% of the RAM, whichever is more; the window shows that number for this Mac. 1 GB steps. |
| Context (tokens) | 8192 | `--max-context` for the engine. Slider over 1024, 2048, 4096, 8192, 16384 and 32768. |
| Prompt chunk | Auto | `STRATA_METAL_PROMPT_CHUNK`: 1024, 2048, 4096 or 8192 tokens. Auto is the engine's choice: 2048 for a resident model and, when the experts stream, 4096 from 96 GiB of RAM and 1024 below; the window shows the number for this Mac. |
| Port | 8080 | Must be between 1024 and 65535; an invalid entry keeps the previous value. |
| Idle unload | Never | `idle_unload_s`: 5, 10, 15, 30, 60 or 120 minutes without requests, after which the server ends the engine process and starts it again for the next request. |
| Fit max_tokens | off | `fit_max_tokens`: clamp a request's max_tokens to the remaining context instead of answering 400. A prompt that is itself longer than the context is still rejected. |
| Verify window | As set up | `--spec`, 2 to 8: how many tokens the MTP drafter proposes per check. "As set up" keeps what setup wrote (2, or 3 for a streaming Mac that keeps the draft layer). Without an MTP draft layer (`--mtp`) in the model's config the value has no effect; the window says so. |

A fixed expert cache is only the arena the engine keeps the most-used experts
in. It is not a limit on Strata's total memory: with a 5 GB cache the engine's
footprint was about 13 GB after start on an M-series Mac with 32 GiB. A fixed
value is never shrunk automatically when memory runs short; an automatic one is
sized from what macOS can give and filled in steps. Any value in the offered
range is accepted; the app only warns, with the reason, for fixed caches under
2 GB (the engine needs about 1.36 GB of the arena for a prompt's buffers and
failed at about 0.8 GB) or over half of the Mac's memory, for contexts over
8192 (untested, more memory), for keeping less than 7 GB for macOS (a 34-minute
run that kept 5 GB swapped out 93 MB while the arena filled), for verify windows
of 5 or more (measured slower) and for prompt chunks above this Mac's default on
a streaming model (their buffers come out of the arena: 4.3 GB at 4096).

Settings are saved in the app's user defaults and apply at the next start.
While a server is running, the window shows the settings it was started with.
**Apply and Restart Server** saves the draft and restarts with it; when the
draft is applied but the saved settings differ from the running ones, **Stop
and Apply Saved Settings** restarts with the saved values. Both buttons (and the menu's) are
disabled while the selected model's installation check fails, so a working
server is not stopped for a launch that cannot succeed. The app never restarts
the server on its own.

At each start the app reads the selected model's `strata-<model>.json` from the
Strata directory and writes a copy with only the managed keys changed to
`~/Library/Application Support/StrataMenubar/strata-<model>.run.json`: the
`--max-context` argument; `--spec` when the verify window is changed;
`STRATA_METAL_ARENA_GB` for a fixed cache; `STRATA_METAL_KEEP_FREE_GB` and
`STRATA_METAL_PROMPT_CHUNK` when set; `idle_unload_s` unless Never;
`fit_max_tokens` when on; the engine log path and the port. A managed key whose
setting is left to the engine is removed even when the base config carries it;
everything else, `STRATA_METAL_STREAM` included, is copied as it is. The
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

### Clients

Clients reach the server at `http://127.0.0.1:<port>/v1` and address the model
by the name `/v1/models` reports (`qwen3.8-flash-next-q2_0` for the Q2_0
pack). After changing the port or the model here, update your clients
yourself; the app does not touch their configuration.

## Limitations

- Only models that Strata's setup has already installed; image input, the MTP
  draft layer and every engine option not listed above stay as the model's base
  config has them.
- No login item, launchd service, LAN access, authentication, signing or
  notarisation.
- A server left over from an app crash is shown as "External Strata" and is not
  adopted; stop it yourself before starting a new one.

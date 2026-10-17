# strata-menubar

A small macOS menu bar app that starts and stops a locally installed
[Strata](https://github.com/Niko1221/Strata) server running Qwen3.8-Flash-Next,
lets you pick which model to run, downloads and deletes models, and changes its
memory, idle-unload and engine settings. It replaces the terminal pane you would
otherwise keep open for `run-<model>.sh`; once the server is up, clients use it as
before.

The app does not install or update Strata itself and does not edit its files.
Models are downloaded and prepared by Strata's own setup, which the app runs when
you ask for it; a deletion moves a model's files to the Trash after asking.

## Requirements

- macOS 15 or newer on Apple Silicon
- Xcode 16 or newer to build (Xcode 27 was used)
- A Strata checkout whose `setup.sh` has run at least once, by default at
  `~/Strata`, containing `.venv/bin/python`, `serve/server.py` and `setup.py`.
  Models set up from a terminal (a `strata-<model>.json`, for example
  `strata-q2_0.json`) are picked up, and more can be downloaded from the app.

## Build

```sh
xcodebuild -project StrataMenubar.xcodeproj -scheme StrataMenubar -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The app lands in `.build/DerivedData/Build/Products/Debug/StrataMenubar.app`.
No Apple developer account is needed; the binary is ad-hoc signed. Start it from
Finder or with `open .build/DerivedData/Build/Products/Debug/StrataMenubar.app`.
It shows an S in the menu bar and nothing in the Dock: filled while the server it started
is running, outlined otherwise.

Tests, project layout and the rules for changing the code are in
[AGENTS.md](AGENTS.md).

## Use

The menu shows one of these states:

| State | Meaning |
| --- | --- |
| Stopped | No Strata server is known on the configured port. The app only looks for Strata; another service holding the port is reported when you press Start. |
| Starting | The server this app started is loading the model, or setup is preparing a downloaded model for its first start ("preparing iq3_s…"). |
| Running | `/health` reports the model as loaded; the line shows model, context and port. On a server started with idle unload, an unloaded model is shown as "(model unloaded after idle; loads on the next request)" with a moon icon, because the server does not say whether it is idle or loading again. |
| Stopping | The server and its engine are shutting down. |
| External Strata | A Strata server somebody else started is listening on the port. The app never stops it. |
| Error | A launch, a preparation or a stop failed, the server exited on its own, or the port is held by something that is not Strata; the message says what to look at. A failing health check of a running server is shown on the Running line instead. |

Actions:

- **The setup line**, for example "Downloading IQ3_S: 45% (37.6 / 83.6 GB)" or
  "Preparing IQ3_S…", appears while the app runs Strata's setup and then keeps
  the result (installed, downloaded, stopped or failed) until the next run. It
  opens the settings window.
- **Settings for the next start** lists the saved values read-only: model,
  expert cache (Auto or a fixed size), context, port and idle unload always; the
  kept memory, verify window, prompt chunk and fit max_tokens only when they are
  not left to the engine or to setup. A row whose value differs from the running
  server's adds "(running: …)". Any row opens the settings window; the menu
  itself changes nothing. A running server keeps the values it was started with
  until you choose **Stop and Apply Saved Settings**.
- **Start Server** starts `serve/server.py` with the saved settings, bound to
  `127.0.0.1` only. The server and the Metal engine it spawns run in their own
  process group owned by the app. A downloaded model is prepared first (see
  [Models](#models)). While a download's setup is preparing its model, Start
  waits until it is done: the preparation must not run beside a loaded engine.
- **Stop Server** sends SIGTERM to the server so it can shut the engine down
  itself, waits for that, and then terminates (and if necessary kills)
  whatever is left in the group. Stopping can take up to about two minutes
  (90 s for the server to close the engine itself, then 20 s and 10 s for
  anything left); the engine frees its memory first. During a preparation, Stop
  stops setup instead and nothing is started.
- **Stop and Apply Saved Settings** appears when the saved settings differ from
  the ones the running server was started with. A value the cache mode does not
  use (the fixed size while Auto is on, the kept memory while it is off) does
  not count.
- **Open Chat** opens Strata's web page of the server that is actually
  listening (its own port, not a newly saved one).
- **Open Server Log** / **Open Engine Log** / **Open Setup Log** / **Show Logs
  in Finder** open the files under `~/Library/Logs/StrataMenubar/`. `server.log`
  is the Python server's stdout and stderr; `engine.log` is what the engine
  writes; `setup.log` collects every setup run the app starts. A file over 10 MB
  is moved to `.1` at the next start or setup run.
- **Quit** asks for confirmation while a server the app started is running or
  starting, or while a download runs; one dialog names both. It stops them first
  (a stopped download resumes with the next Download) and keeps the app open if
  you cancel. A server or a setup the app did not start is left alone.

## Settings

Open **Settings…** from the menu (or ⌘,). The window edits a draft: change
the sliders, the model picker or the text fields, then press **Apply** to save
(it is disabled while a value is invalid) or **Revert** to go back to the
saved values. Closing the window or quitting the app with unapplied changes
asks whether to discard them (Keep Editing is the default answer). The menu
bar only lists the saved values.

| Setting | Default | Notes |
| --- | --- | --- |
| Strata directory | `~/Strata` | Must contain `.venv`, `serve/server.py` and `setup.py`. The window lists what is missing. |
| Model | `q2_0`, else the first installed | One of the `strata-<model>.json` files in the Strata directory, or a downloaded pack, which its first start prepares. |
| Expert cache | Auto | With the toggle on, the engine sizes the expert arena itself and `STRATA_METAL_ARENA_GB` is not written. With it off, the slider sets a fixed size in decimal GB, from 1 GB to the Mac's physical memory in 1 GB steps (5 GB when first switched). A cache saved by an earlier version of this app stays fixed. |
| Keep free for macOS | Engine default | `STRATA_METAL_KEEP_FREE_GB`, only with an automatic cache: what the engine leaves to macOS while it sizes the arena. The engine's own rule is 7 GB or 15% of the RAM, whichever is more; the window shows that number for this Mac. 1 GB steps. |
| Context (tokens) | 8192 | `--max-context` for the engine. Slider over the powers of two from 1024 to 262144, the model's trained length. |
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
32768 (Strata measured the Mac engine to 32K and its setup offers up to 128K;
the KV cache took about 14.5 KB per token: 7.0 GB before the expert arena at
262144 against 3.7 GB at 32768 on a 32 GiB Mac), for keeping less than 7 GB for macOS (a 34-minute
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
everything else, `STRATA_METAL_STREAM` included, is copied as it is. A start
never modifies the original file, `run-<model>.sh` or the model files.

### Models

The window's Models section holds the model picker and a row for each pack
Strata's Mac documentation describes (Q2_0, IQ3_XXS, IQ3_S, UD-Q4_K_XL,
UD-Q5_K_XL, UD-Q6_K_XL). A row shows the pack's state (Installed, Downloaded,
Partially downloaded, Not downloaded, or what setup is doing with it), its
download size, the file the GPU maps, the memory it needs, the recommended RAM
and the disk a finished setup takes on this Mac. Below the rows are the free
space in Strata's data directory and **Open Setup Log**. Download and Delete act
on the saved Strata directory only; apply a new directory first. Models set up
or removed from a terminal show up within a second or so, in the window and in
the menu, without restarting the app.

- **Download** runs Strata's own setup for the pack in the Strata directory,
  as a process the app owns, with its output in `setup.log`:

  ```sh
  .venv/bin/python setup.py --setup --model IQ3_S --no-start --vision no
  ```

  The row shows a progress bar: the share of the download while the shards
  arrive, the step otherwise. One setup runs at a time, and the server can be
  started, stopped and restarted meanwhile. When the checkout has changed since
  setup last ran, setup first updates its Python packages and rebuilds the
  engine, which can take several minutes before the download starts.
- After the download, setup prepares the pack for Strata, which moves well over
  100 GB on disk and must not run beside a loaded engine. When a server is up at
  that point (an external one, or one whose model is unloaded after idle), the
  app stops setup there and the pack is **Downloaded (prepared at the first
  start)**. Otherwise setup goes on, the pack becomes **Installed**, and Start
  waits for it.
- A downloaded pack can be picked as the model like an installed one. Its first
  **Start Server**, **Stop and Apply Saved Settings** or **Apply and Restart
  Server** stops the old server, runs the same setup command to prepare the pack
  (the download is skipped) and then starts the server. The preparation does not
  count toward the start's 600-second limit; if it fails, no server is started
  and the error points at the setup log.
- **Cancel** interrupts setup (SIGINT, then SIGTERM after 20 s and SIGKILL after
  20 s more). The files stay, and **Resume** runs the same command, which
  continues the download where it stopped.
- Download is disabled, with the reason, while the data directory has less free
  space than the disk estimate plus 10 GB (a resume only needs what is still
  missing), while another setup runs, and while a setup started from a terminal
  works on the pack. Such a setup is found by its `setup_mac.py` command line;
  one without `--model` counts for every pack. The app never takes it over.
- **Delete…** lists what goes and its total size, and moves it to the Trash
  after you confirm: the model's `strata-<model>.json`, `run-<model>.sh` and
  `strata-<model>.log`, this app's run config, the model's folder under
  `models/`, its pack and, for the Unsloth packs, the repacked file. Strata's
  shared files (the engine, `.venv`, `mtp/`, the expert profile) and anything
  another installed model's config points at stay. Delete is disabled while the
  model is running or starting (on an external server too), while the server is
  stopping, and while a setup works on the pack. The saved settings are not
  changed; a deleted model shows as "(not installed)" in the picker.

To set a model up from a terminal instead, run the same setup yourself:

```sh
cd "/path/to/Strata" && ./setup.sh --setup --model IQ3_S --no-start --vision no
```

`--no-start` keeps setup from starting a server of its own, and `--vision no`
answers its question about image input.

### Clients

Clients reach the server at `http://127.0.0.1:<port>/v1` and address the model
by the name `/v1/models` reports (`qwen3.8-flash-next-q2_0` for the Q2_0
pack). After changing the port or the model here, update your clients
yourself; the app does not touch their configuration.

## Limitations

- Only the packs Strata's Mac setup offers, set up without image input
  (`--vision no`); the MTP draft layer and every engine option not listed above
  stay as the model's base config has them. Setup's other options (`--update`,
  `--build`, `--context`, …) and installing or updating Strata are left to the
  terminal.
- One setup at a time. A setup started from a terminal is respected but not
  followed or taken over.
- Delete moves files to the Trash; the space comes back only once the Trash is
  emptied.
- No login item, launchd service, LAN access, authentication, signing or
  notarisation.
- A server left over from an app crash is shown as "External Strata" and is not
  adopted; stop it yourself before starting a new one. A setup left over from a
  crash counts as one started outside the app and blocks Download and Delete of
  its pack until it ends.

## Credits

The menu bar S is the `stripe-s` brand icon from Font Awesome Free
(icons: [CC BY 4.0](https://fontawesome.com/license/free)), used as it is and as an outline.

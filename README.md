# strata-menubar

A small macOS menu bar app that starts and stops a locally installed
[Strata](https://github.com/Niko1221/Strata) server running Qwen3.8-Flash-Next
Q2_0, and lets you change its memory-related settings. It replaces the terminal
pane you would otherwise keep open for `run-q2_0.sh`; once the server is up,
clients such as [Pi](https://github.com/badlogic/pi-mono) use it as before.

The app does not install, update or edit Strata or its model files. It needs a
finished Strata setup and runs only the Q2_0 configuration.

## Requirements

- macOS 15 or newer on Apple Silicon
- Xcode 16 or newer to build (Xcode 27 was used)
- A working Strata checkout with the Q2_0 model set up by `setup.sh`, by
  default at `~/Dev/local/Strata`, containing `.venv/bin/python`,
  `serve/server.py` and `strata-q2_0.json`

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

## Use

The menu shows one of these states:

| State | Meaning |
| --- | --- |
| Stopped | Nothing listens on the configured port. |
| Starting | The server this app started is loading the model. |
| Running | `/health` reports the model as loaded; the line shows model, context and port. |
| Stopping | The server and its engine are shutting down. |
| External Strata | A Strata server somebody else started is listening on the port. The app never stops it. |
| Error | A launch, health check or stop failed; the message says what to look at. |

Actions:

- **Start Server** starts `serve/server.py` with the saved settings, bound to
  `127.0.0.1` only. The server and the Metal engine it spawns run in their own
  process group owned by the app.
- **Stop Server** sends SIGTERM to the server so it can shut the engine down
  itself, waits for that, and then terminates (and if necessary kills)
  whatever is left in the group. Stopping can take up to a minute or so; the
  engine frees its memory first.
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

Open **Settings…** from the menu (or ⌘,).

| Setting | Default | Notes |
| --- | --- | --- |
| Strata directory | `~/Dev/local/Strata` | Must contain a finished setup. The window lists what is missing. |
| Expert cache (GB) | 5 | `STRATA_METAL_ARENA_GB`, in decimal GB. |
| Context (tokens) | 8192 | `--max-context` for the engine. |
| Port | 8080 | Must be between 1024 and 65535. |

The expert cache is only the arena the engine keeps the most-used experts in.
It is not a limit on Strata's total memory: with a 5 GB cache the engine's
footprint was about 10.6 GB on an M-series Mac with 32 GiB. A fixed value is
never shrunk automatically when memory runs short, and "about 16 GB overall" is
an operating goal, not something the app enforces. Values that have not been
tried here (caches under 3 GB or over 12 GB, contexts other than 8192) are
flagged as warnings but allowed.

Settings are saved in the app's user defaults and apply at the next start.
While a server is running, **Save** keeps it as it is and **Save, Stop and
Apply** restarts it with the new values. The window shows the settings the
running server was started with next to the saved ones. The app never
restarts the server on its own.

At each start the app reads the current `strata-q2_0.json` from the Strata
directory and writes a copy with only the managed keys changed
(`--max-context`, `STRATA_METAL_ARENA_GB`, the engine log path and the port)
to `~/Library/Application Support/StrataMenubar/strata-q2_0.run.json`. The
original file, `run-q2_0.sh` and the model files are never modified.

### Pi

Pi reads this server through its `strata` provider entry in
`~/Dev/local/.pi/models.json` (`http://127.0.0.1:8080/v1`, `contextWindow`
8192, `maxTokens` 2048). After changing the port or the context here, edit that
file by hand; the app does not touch Pi's configuration.

With the 8192 context, Pi's default coding system prompt plus its built-in
tools did not fit: the server answered 400 because the prompt alone was 8,326
tokens. A short question worked with tools off and a small system prompt, for
example:

```sh
pi -p --no-tools --system-prompt "You are a terse assistant." \
  --provider strata --model qwen3.8-flash-next-q2_0 "Reply with the single word: pong"
```

## Limitations

- Q2_0 only; image input and the MTP draft stay off, as in the base config.
- No login item, launchd service, LAN access, authentication, signing or
  notarisation.
- A server left over from an app crash is shown as "External Strata" and is not
  adopted; stop it yourself before starting a new one.

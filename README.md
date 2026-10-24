# Factory Night Watch

Keep your cooperative Factorio factory running while everyone is offline, with
configurable safety pauses when something needs attention.

**Development version 0.3.2 · Factorio 2.1.23 · Space Age supported · English / Deutsch**

[Deutsche Anleitung](docs/README.de.md) · [Validation](docs/TESTS.txt) ·
[Changelog](mod/changelog.txt)

## Features

- Pause on structure destruction, an empty research queue, or an offline time limit.
- Default time limit: 7 simulation days; configurable or unlimited.
- Optional named circuit conditions: select a wired pole, red/green network,
  signal and quality, comparison, threshold and continuous delay.
- Live signal values; offline safety pause if an enabled rule loses its pole or cable.
- Bottom-right native shortcut with Overview, Rules and Advanced tabs.
- Admin-only changes, save/discard drafts and confirmation before a test pause.
- Persistent safety alarms, offline timers and circuit rules across save/reload.
- Jump to the alarm location in remote view while keeping the safety pause active.
- Three rotating emergency saves; synthetic sandbox surfaces are excluded.

Protection pauses stop the whole simulation and require admin acknowledgement.
They do not automatically roll back damage. Ordinary empty-server pauses resume
when someone joins. AFK players still count as online.

## Install

Build the distribution using Python 3 (standard library only):

```sh
python3 tools/build.py
```

Copy `dist/factory-night-watch_0.3.2.zip` into each client's Factorio `mods`
directory without extracting it. Remove older ZIP versions and restart Factorio.
All clients and the server need the same version. This development build is not
yet published on the Factorio Mod Portal.

Open the bottom-right radar shortcut, or use `/fnw-gui`. `/fnw-status` is readable
by everyone; `/fnw-resume`, `/fnw-test-pause` and `/fnw-set` require an admin.

An optional Docker installer is generated as `dist/install-factory-night-watch.sh`.
It is specific to a `factoriotools/factorio` layout with container name `factorio`,
`compose.yaml`, a `/factorio` data bind mount and UID/GID 845. Read the script before
running it. It briefly stops Factorio, creates a rollback snapshot and changes
`auto_pause` to false. Other layouts can install the ZIP manually, with server
`auto_pause=false` for protected offline running.

## Updates directly from GitHub

[Server setup and update commands](docs/UPDATES.md). After the one-time GitHub CLI
login and command setup, run `~/.local/bin/factorio-mod-update` as your normal
server user. The updater downloads a fixed commit, builds the ZIP and invokes
the existing installer using sudo. It creates a rollback snapshot before changing
the installation. An unchanged installed commit does not restart Factorio.
This is on-demand deployment; it does not run unattended or update Factorio itself.
All clients still need the same mod version. `--build-only DIRECTORY` builds
files without touching a server.

## Circuit conditions

Under **Advanced**, add a condition and select a network by dragging a small box
around one wired electric pole. Choose red or green, a signal, an operator and a
threshold. Set how many consecutive simulation seconds it must remain true.
Save the draft to activate it. Put complex AND/OR logic in ordinary combinators.

Rules are sampled once per simulation second. An absent signal in an intact
network reads zero. A missing source or cable triggers a safety pause while
offline. Online, rules only show their live state. Multiple enabled rules act
as OR: any one can pause the world. Clear the cause before acknowledging.

## Development

```sh
python3 tests/run.py
python3 -m unittest discover -s tests -p test_update.py
python3 tools/build.py
```

The first command runs 54 GUI/presence checks with Lua mocks. Install Lua 5.4 or
its shared library. The build validates metadata, matching locale keys, archive
integrity, embedded installer Python and shell syntax when Bash is available.

Real engine integration tests require a local **Factorio headless 2.1.23** with
Space Age data. They create their own maps and test-only mod copy:

```sh
FACTORIO_BIN=/path/to/factorio/bin/x64/factorio python3 tests/integration.py
```

Ports 34997/UDP and 27995/TCP must be free. Both listeners bind to localhost.
Generated test data goes into ignored `build/integration/`. Never point tests at
a production installation or save. The test-only bridge is excluded from builds.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution workflow.

## Release readiness

32 actual engine checks and 54 mock checks passed for 0.3.2. Native Windows GUI
rendering and mouse interaction still need an in-game check. Backups remain
necessary. There is no separate platform-hub health rule.

Licensed under the [MIT License](LICENSE). Copyright (c) 2026 dermalla.
The repository is currently private and the mod has not been published to the Mod Portal.

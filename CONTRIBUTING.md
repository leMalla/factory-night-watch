# Contributing

Keep changes focused and describe the player-visible behavior. Maintain the
German and English locale catalogs together. Preserve offline timers and safety
latches when modifying saved state; do not silently release existing alarms.

Run `python3 tests/run.py`, `python3 -m unittest discover -s tests -p test_update.py`,
and `python3 tools/build.py` before submitting changes.
For protection logic, also run `tests/integration.py` with Factorio 2.1.23 and
Space Age data. Include the results and any limits in the pull request.

Never commit game saves, server settings, RCON passwords, account tokens,
downloaded Factorio binaries, or logs containing personal server information.
Use a fresh test map and sanitized reproduction details.

Before a release, bump `mod/info.json`, update `mod/changelog.txt` and the docs,
test the GUI in a real client, and build the ZIP. The build reads the version
from `info.json`; generated `dist/` files belong in release assets rather than
source commits. The project uses the MIT license. Public releases are still pending.

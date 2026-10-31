# Contributing

Keep changes focused and describe the player-visible behavior. Maintain the
German and English locale catalogs together. Preserve offline timers and safety
latches when modifying saved state; do not silently release existing alarms.

Run `python3 tests/run.py`, `python3 -m unittest discover -s tests -p 'test_*.py'`,
and `python3 tools/build.py` before submitting changes.
For protection logic, also run `tests/integration.py` with Factorio 2.1.23 and
Space Age data. Include the results and any limits in the pull request.

Never commit game saves, server settings, RCON passwords, account tokens,
downloaded Factorio binaries, or logs containing personal server information.
Use a fresh test map and sanitized reproduction details.

Before a release, bump `mod/info.json`, update `mod/changelog.txt` and the docs,
test the GUI in a real client, and build the ZIP. The build reads the version
from `info.json`; generated `dist/` files belong in release assets rather than
source commits. The project uses the MIT license. Version 0.3.10 was published
on the Factorio Mod Portal on 2026-10-31.

## Branch and release workflow

- Start each feature, fix or maintenance change on a short-lived branch from `main`.
- Open a pull request with player-visible behavior, validation results and limits.
- Merge after the maintainer’s review and any required in-game test.
- Remove merged branches only after confirming they contain no unmerged commits.
- Keep `main` usable by the server updater; changes there can trigger a reinstall.
- Identify a published version with a `vX.Y.Z` tag at its tested source commit.
  Keep the Factorio ZIP structure and version unchanged between server, clients
  and the Mod Portal. Do not rewrite published tags or repository history.

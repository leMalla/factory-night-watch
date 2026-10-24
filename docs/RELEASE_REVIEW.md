# Release review — 0.3.4 candidate

Date: 2026-10-24. Three independent agent reviews covered runtime safety,
GUI/state handling, and distribution/installer behavior. The maintainer reported
that the previous 0.3.3 build works in the real game client. No public upload or
repository-visibility change was made during this review.

## Confirmed findings and fixes

| Area | Finding | Resolution |
| --- | --- | --- |
| Installer | Compose stop/up could affect unrelated services | Resolve and validate the Factorio container's project/service; target that service with `up --no-deps` |
| Installer | An unpacked higher-version mod could override the ZIP | Reject matching unpacked directories before shutdown, without deleting the checkout |
| Installer | Snapshot-read failure could leave Factorio stopped | Read original files/JSON before stop and protect the entire stopped lifecycle with recovery |
| GUI | An old draft could overwrite newer global settings | Refresh clean forms; reject stale dirty forms with an actionable conflict message |
| GUI | Other open windows could stay stale while paused | Refresh all forms after a completed apply transaction |
| Player lifecycle | Reused player index could inherit a removed player's draft | Clear per-player GUI state and close guards on player removal |
| Pause ownership | Empty-server mode could release an existing manual pause | Claim only pauses created by Night Watch |
| Build | PNG thumbnails were rejected | Allow PNG assets; verify a thumbnail fixture is included unchanged |
| Documentation | Backup text assumed an existing daily-backup setup | Describe emergency saves as no replacement for regular backups |

No further confirmed runtime crash was found by the reviewers. This is an
engineering review with the limits below, not a guarantee that every mod
combination or native UI path has been exercised.

## Validation

- 36 checks with actual Factorio headless 2.1.23 and Space Age.
- 32 checks with actual Factorio headless 2.1.23, base game only.
- 82 GUI/presence checks, including native-close simulation, admin rights,
  saved coordinates, network IDs, stale drafts and paused multi-player refresh.
- 14 installer failure-injection tests using real temporary files/tar archives,
  with Docker and ownership changes mocked.
- 8 updater tests for authenticated-download/build/install control flow.
- Both engine configurations include 32 active rules over five simulation minutes.
- Failure tests include readiness timeout, exit 137 and failed backup validation.
- ZIP integrity, MIT license inclusion, locale keys, embedded Python and shell
  syntax checked by the build; a separate PNG packaging fixture passed.

See [TESTS.txt](TESTS.txt) for scope and commands in [README.md](../README.md).
The reviews did not access or publish private server logs or account secrets.

## Final live smoke test

1. Update server and all clients to the same candidate version.
2. Add a circuit rule, select its network, save, close and reopen the window.
3. Test and acknowledge a safety pause; verify the saved location can be viewed.
4. With an untouched GUI open, change a setting through `/fnw-set`; the clean
   form should follow it. With an edited draft, a subsequent external change
   should cause Save to show a conflict until the draft is discarded.
5. Run the updater again without a new GitHub commit; it should skip restart.

## Portal preparation

The ZIP has valid naming, metadata, changelog and the MIT license. Add a portal
description from [MOD_PORTAL.md](MOD_PORTAL.md), copy the [FAQ](MOD_PORTAL_FAQ.md),
select Utilities and MIT, and upload the tested ZIP under the
maintainer's Factorio account when ready. A 144×144 thumbnail and current GUI
screenshots are recommended presentation assets, not required runtime files.
The GitHub repository is still private; making it public is a separate release
decision. No Mod Portal release has been published yet.

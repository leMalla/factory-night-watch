# Updates direkt von GitHub

Der Updater lädt `leMalla/factory-night-watch` direkt von GitHub. Der Server
meldet sich einmal bei GitHub an. Danach ist kein WinSCP mehr erforderlich.
Die Anmeldung in ChatGPT und die Anmeldung auf deinem Server sind getrennt.

## Einmalig auf dem Ubuntu-Server

Als normaler SSH-Benutzer ausführen, nicht als root:

```bash
sudo apt update
sudo apt install -y gh python3
gh auth login --hostname github.com --git-protocol https --web
```

Den angezeigten Gerätecode am eigenen PC unter der von GitHub angegebenen URL
bestätigen. Mit dem Konto anmelden, das Zugriff auf das Repository hat.
Die Git-Authentifizierung muss für diesen API-basierten Updater nicht eingerichtet
werden. Keine Tokens in den Chat oder in Shell-Befehle kopieren.

Danach den Updatebefehl einrichten:

```bash
bash -e -o pipefail <<'SETUP'
mkdir -p "$HOME/.local/bin"
target="$HOME/.local/bin/factorio-mod-update"
temporary="$(mktemp "$HOME/.local/bin/factorio-mod-update.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
gh api --hostname github.com repos/leMalla/factory-night-watch/contents/tools/update.py --jq '.content' | base64 --decode > "$temporary"
python3 - "$temporary" <<'PY'
import ast, sys
from pathlib import Path
ast.parse(Path(sys.argv[1]).read_text())
PY
chmod 700 "$temporary"
mv "$temporary" "$target"
echo "Eingerichtet: $target"
SETUP
```

## Aktualisieren

```bash
~/.local/bin/factorio-mod-update
```

Standardordner: `~/docker/factorio`, beim ursprünglichen Server also
`/home/<benutzer>/docker/factorio`. Für einen anderen Ort:

```bash
~/.local/bin/factorio-mod-update --project /pfad/zum/factorio-projekt
```

Ohne sudo starten, damit die GitHub-Anmeldung deines normalen Benutzers verwendet
wird. Erst der vorhandene Installer fordert bei Bedarf sudo an. Er sichert und
stoppt Factorio, ersetzt die Mod, startet den Server und prüft auf `InGame`.
Konfiguration und Spielstand bleiben erhalten; `auto_pause` wird auf false gesetzt.
Andere Container und die Factorio-Version werden nicht aktualisiert.

Der Updatebefehl lädt standardmäßig den aktuellen Stand von `main`, aufgelöst
zu genau einem Commit. Auch Änderungen ohne neue Versionsnummer werden dadurch
installiert. Für einen gezielten Stand: `--ref COMMIT-ODER-TAG`. Es gibt keinen
Timer und keine automatische Übernahme neuer GitHub-Commits im Hintergrund.

Ein bereits erfolgreich installierter Commit mit unveränderter Mod-Datei wird
übersprungen. `--force` erzwingt die Neuinstallation. Nach erfolgreicher
Installation aktualisiert sich auch der eingerichtete Updatebefehl selbst.
Der lokale Nachweis liegt unter `~/.local/state/factory-night-watch/`.

Nur prüfen:

```bash
~/.local/bin/factorio-mod-update --check
```

Nur ZIP und Installer bauen, ohne Serverzugriff und ohne Neustart:

```bash
~/.local/bin/factorio-mod-update --build-only "$HOME/factorio-mod-download"
```

## Clients

Server und Clients müssen dieselbe Mod-Version haben. Dieser Befehl aktualisiert
den Docker-Server; ein laufendes Windows-Spiel wird dadurch nicht geändert.
Die erzeugte Mod-ZIP lässt sich in den lokalen Factorio-Mods-Ordner kopieren.
Nach Veröffentlichung im Factorio-Modportal kann Factorio die normale
Mod-Synchronisierung beim Beitritt übernehmen.

## Rücksetzpunkte

Vor jeder tatsächlichen Installation legt der Installer einen Rücksetzpunkt
unter `backups/night-watch-install/` im Factorio-Projekt an. Die vorhandenen
täglichen Backups bleiben erhalten. Die GitHub-Anmeldung gehört zum normalen
Benutzerprofil und wird nicht in diese Projekt-Backups aufgenommen.

## English

Install GitHub CLI and Python 3, then authenticate as the normal server user with
`gh auth login --hostname github.com --git-protocol https --web`. Install the
updater using the setup block above. Run `~/.local/bin/factorio-mod-update`
without sudo; only the underlying Docker installer needs elevated privileges.
The command resolves `main` to a fixed commit, downloads and builds it, then
installs it with the existing rollback snapshot mechanism. Unchanged installations
do not restart the server. `--check`, `--ref` and `--build-only` are available.
This is an on-demand server update, not an unattended deployment or client update.

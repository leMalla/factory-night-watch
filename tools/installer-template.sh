#!/bin/bash
set -Eeuo pipefail
if [ "$(id -u)" -ne 0 ]; then
    echo "Bitte mit sudo bash install-factory-night-watch.sh starten."
    exit 1
fi

python3 - "$@" <<'PY'
import base64
import fcntl
import hashlib
import io
import json
import os
import stat
import subprocess
import sys
import tarfile
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path

PAYLOAD = """__MOD_BASE64__"""
SHA256 = "__MOD_SHA256__"
NAME = "factory-night-watch"
VERSION = "0.3.0"
sudo_user = os.environ.get("SUDO_USER")
if len(sys.argv) <= 1 and (not sudo_user or sudo_user == "root"):
    raise SystemExit("Bitte den Factorio-Projektpfad als Argument angeben.")
root = Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else Path("/home") / sudo_user / "docker/factorio"
compose = ["docker", "compose", "-f", str(root / "compose.yaml")]
os.umask(0o077)

# Regular backups use the same lock. Do not stop the server underneath a backup.
lock = open("/run/lock/factorio-backup.lock", "w")
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    raise SystemExit("Ein Backup/Installer laeuft bereits. Bitte spaeter erneut versuchen.")

payload = base64.b64decode(PAYLOAD)
if hashlib.sha256(payload).hexdigest() != SHA256:
    raise SystemExit("Installer-Daten beschaedigt; nichts veraendert.")
with zipfile.ZipFile(io.BytesIO(payload)) as z:
    if z.testzip():
        raise SystemExit("ZIP-Pruefung fehlgeschlagen.")
    info = json.loads(z.read(f"{NAME}_{VERSION}/info.json"))
    if info["name"] != NAME or info["version"] != VERSION:
        raise SystemExit("Unerwartete Mod-Metadaten.")

settings_path = root / "config/server-settings.json"
list_path = root / "mods/mod-list.json"
target = root / "mods" / f"{NAME}_{VERSION}.zip"
if not settings_path.is_file() or not (root / "compose.yaml").is_file():
    raise SystemExit("Factorio-Konfiguration am erwarteten Ort nicht gefunden.")

configuration = json.loads(subprocess.check_output(
    compose + ["config", "--format", "json"], text=True
))
labels = json.loads(subprocess.check_output(
    ["docker", "inspect", "--format", "{{json .Config.Labels}}", "factorio"], text=True
)) or {}
service = labels.get("com.docker.compose.service")
project = labels.get("com.docker.compose.project")
if not service or service not in configuration.get("services", {}):
    raise SystemExit("Factorio-Compose-Service stimmt nicht mit compose.yaml ueberein; nichts veraendert.")
if not project or configuration.get("name") != project:
    raise SystemExit("Factorio gehoert zu einem anderen Compose-Projekt; nichts veraendert.")
mounts = json.loads(subprocess.check_output(
    ["docker", "inspect", "--format", "{{json .Mounts}}", "factorio"], text=True
))
if not any(m["Destination"] == "/factorio" and Path(m["Source"]) == root for m in mounts):
    raise SystemExit("Container verwendet einen anderen Datenpfad; nichts veraendert.")
stop = compose + ["stop", "-t", "120", service]
start = compose + ["up", "-d", "--no-deps", service]

# Factorio may prefer an unpacked/higher-version mod over the installed ZIP.
# Refuse this ambiguous layout before stopping; never delete a user's checkout.
for directory in (root / "mods").iterdir():
    if not directory.is_dir():
        continue
    metadata = directory / "info.json"
    try:
        unpacked_name = json.loads(metadata.read_text()).get("name")
    except (OSError, ValueError, AttributeError):
        if directory.name == NAME or directory.name.startswith(NAME + "_"):
            raise SystemExit("Ungeklaerter entpackter Mod-Ordner: " + str(directory) + "; bitte vor dem Update aus mods verschieben.")
        continue
    if unpacked_name == NAME:
        raise SystemExit("Entpackte Factory-Night-Watch-Mod gefunden: " + str(directory) + "; bitte vor dem Update aus mods verschieben.")

obsolete = [p for p in (root / "mods").glob(f"{NAME}_*.zip") if p != target]
originals = {}
for path in (settings_path, list_path, target, *obsolete):
    if path.exists() or path.is_symlink():
        metadata = path.lstat() if path.is_symlink() else path.stat()
        originals[path] = {"data": path.read_bytes(), "uid": metadata.st_uid,
                           "gid": metadata.st_gid, "mode": stat.S_IMODE(metadata.st_mode),
                           "link": os.readlink(path) if path.is_symlink() else None}
    else:
        originals[path] = None

# Parse and prepare all JSON before touching the running service.
settings = json.loads(originals[settings_path]["data"])
listing = json.loads(originals[list_path]["data"]) if originals[list_path] else {
    "mods": [{"name": "base", "enabled": True}]
}
if not isinstance(settings, dict) or not isinstance(listing, dict) or not isinstance(listing.get("mods"), list):
    raise SystemExit("Unerwartete Factorio-Konfiguration; nichts veraendert.")
if not all(isinstance(m, dict) and isinstance(m.get("name"), str) for m in listing["mods"]):
    raise SystemExit("Unerwartete Mod-Liste; nichts veraendert.")
settings["auto_pause"] = False
for old_entry in listing["mods"]:
    if old_entry["name"] == "crackit-offline-guard":
        old_entry["enabled"] = False
if (not any(m["name"] == "crackit-offline-guard" for m in listing["mods"])
        and any((root / "mods").glob("crackit-offline-guard*"))):
    listing["mods"].append({"name": "crackit-offline-guard", "enabled": False})
entry = next((m for m in listing["mods"] if m["name"] == NAME), None)
if entry:
    entry["enabled"] = True
else:
    listing["mods"].append({"name": NAME, "enabled": True})

def write(path, data, uid=845, gid=845, mode=None):
    temporary = Path(str(path) + ".guard-tmp")
    temporary.write_bytes(data)
    os.chown(temporary, uid, gid)
    temporary.chmod(mode if mode is not None else (0o600 if path == settings_path else 0o640))
    temporary.replace(path)

def restore(path, original):
    if original is None:
        path.unlink(missing_ok=True)
    elif original["link"] is not None:
        temporary = Path(str(path) + ".guard-tmp")
        temporary.unlink(missing_ok=True)
        temporary.symlink_to(original["link"])
        os.lchown(temporary, original["uid"], original["gid"])
        temporary.replace(path)
    else:
        write(path, original["data"], original["uid"], original["gid"], original["mode"])

stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
rollback_dir = root / "backups" / "night-watch-install"
rollback_dir.mkdir(parents=True, exist_ok=True)
backup = rollback_dir / f"before-guard-{stamp}.tar.gz"
backup_partial = Path(str(backup) + ".partial")

print("Stoppe Factorio und sichere den bisherigen Stand ...", flush=True)
mutated = False
try:
    subprocess.run(stop, check=True)
    exit_code = subprocess.check_output(
        ["docker", "inspect", "--format", "{{.State.ExitCode}}", "factorio"], text=True
    ).strip()
    if exit_code not in ("0", "143"):
        raise RuntimeError("Kein sauberer Shutdown: Exit " + exit_code)
    saves = [p for p in (root / "saves").glob("*.zip") if not p.name.endswith(".tmp.zip")]
    if not saves:
        raise RuntimeError("Kein Spielstand gefunden.")
    newest = max(saves, key=lambda p: p.stat().st_mtime_ns)
    with tarfile.open(backup_partial, "w:gz") as tar:
        for relative in ("compose.yaml", "config", "mods", "saves/" + newest.name):
            tar.add(root / relative, arcname=relative)
    # Read through all compressed bytes before accepting the rollback snapshot.
    subprocess.run(["gzip", "-t", str(backup_partial)], check=True)
    backup_partial.replace(backup)

    mutated = True
    write(target, payload)
    for path in obsolete:
        path.unlink()
    write(list_path, (json.dumps(listing, indent=2) + "\n").encode())
    write(settings_path, (json.dumps(settings, indent=2, ensure_ascii=False) + "\n").encode())
    since = datetime.now(timezone.utc).isoformat()
    subprocess.run(start, check=True)
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        result = subprocess.run(
            ["docker", "logs", "--since", since, "factorio"],
            capture_output=True, text=True, check=True
        )
        logs = result.stdout + result.stderr
        if "to(InGame)" in logs:
            break
        time.sleep(1)
    else:
        print(logs[-5000:])
        raise RuntimeError("Server wurde nicht innerhalb von 90 Sekunden spielbereit.")
except BaseException:
    errors = []
    if mutated:
        print("Installation fehlgeschlagen. Stelle vorherige Mod-Konfiguration wieder her ...", flush=True)
        try:
            result = subprocess.run(stop, check=False)
            if result.returncode:
                errors.append("Factorio konnte vor dem Ruecksetzen nicht gestoppt werden.")
        except Exception as error:
            errors.append("Stop beim Ruecksetzen fehlgeschlagen: " + str(error))
        for path, original in originals.items():
            try:
                restore(path, original)
            except Exception as error:
                errors.append("Wiederherstellung fehlgeschlagen fuer " + str(path) + ": " + str(error))
    # Every failure after attempting stop must try to return the original service.
    try:
        result = subprocess.run(start, check=False)
        if result.returncode:
            errors.append("Der vorherige Factorio-Service konnte nicht neu gestartet werden.")
    except Exception as error:
        errors.append("Neustart fehlgeschlagen: " + str(error))
    if backup.exists():
        print("Vollstaendiger Ruecksetzpunkt:", backup)
    for error in errors:
        print(error, file=sys.stderr)
    raise
finally:
    for temporary in (backup_partial, *(Path(str(path) + ".guard-tmp") for path in originals)):
        try:
            temporary.unlink(missing_ok=True)
        except OSError as error:
            print("Temporäre Datei konnte nicht entfernt werden: " + str(error), file=sys.stderr)

print("\nFactory Night Watch 0.3.0 mit neuer GUI und Schaltungsregeln installiert; Server ist spielbereit.")
print("Installations-Ruecksetzpunkt:", backup)
print("Jeder Client braucht dieselbe Mod-ZIP im lokalen Factorio-Mods-Ordner.")
print("Test im Spiel: /fnw-test-pause; danach /fnw-resume.")
print("Nur-Produktion ohne Forschung: /fnw-set research-pause false")
PY

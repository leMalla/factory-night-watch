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

subprocess.run(compose + ["config", "--quiet"], check=True)
mounts = json.loads(subprocess.check_output(
    ["docker", "inspect", "--format", "{{json .Mounts}}", "factorio"], text=True
))
if not any(m["Destination"] == "/factorio" and Path(m["Source"]) == root for m in mounts):
    raise SystemExit("Container verwendet einen anderen Datenpfad; nichts veraendert.")

stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
rollback_dir = root / "backups" / "night-watch-install"
rollback_dir.mkdir(parents=True, exist_ok=True)
backup = rollback_dir / f"before-guard-{stamp}.tar.gz"
backup_partial = Path(str(backup) + ".partial")

print("Stoppe Factorio und sichere den bisherigen Stand ...", flush=True)
try:
    subprocess.run(compose + ["stop", "-t", "120"], check=True)
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
except BaseException:
    subprocess.run(compose + ["up", "-d"], check=False)
    raise
finally:
    backup_partial.unlink(missing_ok=True)

originals = {p: p.read_bytes() if p.exists() else None for p in (settings_path, list_path, target)}
obsolete = [p for p in (root / "mods").glob(f"{NAME}_*.zip") if p != target]
for path in obsolete:
    originals[path] = path.read_bytes()

def write(path, data, uid=845, gid=845):
    temporary = Path(str(path) + ".guard-tmp")
    temporary.write_bytes(data)
    os.chown(temporary, uid, gid)
    temporary.chmod(0o640 if path != settings_path else 0o600)
    temporary.replace(path)

try:
    settings = json.loads(originals[settings_path])
    settings["auto_pause"] = False
    listing = json.loads(originals[list_path]) if originals[list_path] else {
        "mods": [{"name": "base", "enabled": True}]
    }
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

    write(target, payload)
    for path in obsolete:
        path.unlink()
    write(list_path, (json.dumps(listing, indent=2) + "\n").encode())
    write(settings_path, (json.dumps(settings, indent=2, ensure_ascii=False) + "\n").encode())
    since = datetime.now(timezone.utc).isoformat()
    subprocess.run(compose + ["up", "-d"], check=True)
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
    print("Installation fehlgeschlagen. Stelle vorherige Mod-Konfiguration wieder her ...", flush=True)
    subprocess.run(compose + ["stop", "-t", "120"], check=False)
    for path, data in originals.items():
        if data is None:
            path.unlink(missing_ok=True)
        else:
            write(path, data)
    subprocess.run(compose + ["up", "-d"], check=False)
    print("Vollstaendiger Ruecksetzpunkt:", backup)
    raise

print("\nFactory Night Watch 0.3.0 mit neuer GUI und Schaltungsregeln installiert; Server ist spielbereit.")
print("Installations-Ruecksetzpunkt:", backup)
print("Jeder Client braucht dieselbe Mod-ZIP im lokalen Factorio-Mods-Ordner.")
print("Test im Spiel: /fnw-test-pause; danach /fnw-resume.")
print("Nur-Produktion ohne Forschung: /fnw-set research-pause false")
PY

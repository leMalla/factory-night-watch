# Factory Night Watch 0.3.3

Offline production for cooperative Factorio 2.1.23 multiplayer servers, including Space Age.
German and English settings, GUI, commands and safety messages. Author: dermalla.

## Bedienung (Deutsch)

Das Radar-Symbol in der Shortcut-Leiste unten rechts öffnet das Fenster. Falls es dort nicht
sichtbar ist, über die Anpassung der Shortcut-Leiste einblenden. Alternativ: `/fnw-gui`.
Der frühere Button oben links wird entfernt.

- **Übersicht:** Betriebsart, aktuelle oder letzte Offline-Laufzeit, verbleibendes Limit und
  letzter Pausengrund mit Position. **Zum Auslöseort** öffnet die Fernansicht an den
  gespeicherten Koordinaten, auch auf einem anderen Planeten oder einer Plattform.
  Die Schutzpause bleibt bestehen; deine Spielfigur bleibt an ihrem Ort. Offene
  Eingaben bleiben beim Wechsel erhalten. Für Zeit-/Forschungspausen ohne Ortsangabe
  erscheint der Knopf nicht. Bei Schutzpause kann ein Admin bestätigen und fortsetzen.
- **Regeln:** Gebäudeverlust, leere Forschung und maximale Offline-Laufzeit.
- **Erweitert:** Ausnahmen für Mauern/Tore und Roboter, Notfallspeicherung, eigene Schaltungen,
  Team-/Weltausschlüsse und eine Testpause mit Bestätigung.

Nur Admins ändern Einstellungen. Speichern übernimmt den gesamten Entwurf; Verwerfen lädt die
aktuellen Einstellungen. Beim Schließen eines ungespeicherten Entwurfs wird nachgefragt.
Laufende Statusanzeigen überschreiben keine Eingaben. Fensterposition und Reiter bleiben erhalten.

### Betriebsarten und Grundregeln

**Geschützt weiterlaufen** ist Standard. Sobald der letzte Spieler geht, startet die Offline-Uhr.
Nach standardmäßig 168 simulierten Stunden (7 Tagen) wird pausiert. Das Zeitlimit ist konfigurierbar
und per Häkchen abschaltbar. Ausschalt- und Pausenzeiten zählen nicht; gespeicherte Offline-Zeit
bleibt über Serverneustarts erhalten. Jeder verbundene Spieler, auch AFK, zählt als online.

**Sofort pausieren** hält einen leeren Server sofort an und setzt beim Beitritt automatisch fort.
Eine bereits ausgelöste Schutzpause bleibt in beiden Betriebsarten bis zur Admin-Bestätigung erhalten.
Das ist seit 0.3.3 auch die Bedeutung von `/fnw-set enabled false`.

Die Forschungsregel wartet standardmäßig 5 Spielminuten ohne gewählte oder eingereihte Forschung
bei ALLEN überwachten Teams. Eine gewählte Forschung ohne Wissenschaftspakete zählt nicht als leer.
Für reine Produktionsnächte lässt sich diese Regel abschalten.

Die Zerstörungsregel reagiert auf gegnerisch verursachten Gebäudeverlust auf Planeten und auf
Gebäudetod auf Plattformen, auch durch Asteroiden. Mauern, Tore und Roboter sind standardmäßig
ausgenommen. Abbau, Rückbau und direktes Löschen per Skript zählen nicht. Es gibt keine separate
Regel für die Restgesundheit des Plattform-Hubs mehr.

### Eigene Schaltungen

1. Unter **Erweitert → Schaltung hinzufügen** einen Namen vergeben.
2. **Netz auswählen** anklicken und einen kleinen Rahmen um genau einen mit Schaltungskabel
   verbundenen Strommast ziehen. Q bricht die Auswahl ab und öffnet den erhaltenen Entwurf.
3. Rot oder Grün auswählen. Die Netze werden getrennt gelesen, ohne sie zusammenzurechnen.
   Angezeigt wird die aktuelle Schaltungsnetz-ID mit Kabelfarbe und Planet/Plattform.
   Die Koordinaten bleiben intern gespeichert, damit der Kartensprung auch nach
   dem Verlust des ausgewählten Masts noch funktioniert.
4. Ein Gegenstands-, Flüssigkeits- oder virtuelles Signal mit gewünschter Qualität wählen.
5. Vergleich (`<`, `≤`, `=`, `≠`, `≥`, `>`), ganzzahligen Wert und Wartezeit eintragen.
6. **Speichern**. Bis dahin bleibt die Regel ein Entwurf.

Beispiel: Munitionssignal `< 100`, durchgehend 60 Sekunden. Komplexe UND/ODER-Logik bleibt in
normalen Kombinatoren; deren Ausgangssignal kann als Regel dienen. Bis zu 32 benannte Regeln.
Jede aktive Regel kann die gesamte Offline-Simulation pausieren. Mit Spielern online dienen die
Regeln nur als Live-Anzeige und sammeln keine Offline-Wartezeit.

Prüfung einmal pro simulierte Sekunde, daher auch bei Wartezeit 0 bis etwa eine Sekunde Latenz.
Eine nicht mehr erfüllte Bedingung setzt die laufende Wartezeit zurück. Ein nicht vorhandenes
Signal in einem intakten Netz hat den Wert 0. Verschwindet dagegen der registrierte Strommast
oder das gewählte Kabelnetz, wird bei aktiver Regel offline eine Schutzpause ausgelöst.
Die GUI zeigt solche Probleme auch online. Quelle reparieren/neu auswählen oder Regel deaktivieren.
Eine deaktivierte Regel mit verlorener Quelle kann gespeichert oder entfernt werden.
Die Zerstörung einer Quelle kann unabhängig davon den allgemeinen Gebäudeverlust-Alarm auslösen.

Verlorene Signale heben eine ausgelöste Pause nicht automatisch auf. Eine Admin-Bestätigung startet
eine neue Offline-Phase mit frischen Wartezeiten; besteht die Ursache weiter, löst sie erneut aus.
Schaltungen gehören in die überwachte Force und auf echte Planeten/Plattformen. Künstliche
Blueprint-Sandboxes-Welten sind immer ausgeschlossen. Standard-Force: `player`.

### Pausen und Speicherung

Eine Schutzpause stoppt die **gesamte Welt**. Beitritt oder gewöhnliches Entpausieren quittieren sie
nicht. GUI oder `/fnw-resume` benutzen. Bis zu drei rotierende Notfallstände werden angefordert:
`factory-night-watch-emergency-1.zip` bis `-3.zip`. Sie speichern den Zustand nach dem Auslöser,
sind kein automatisches Zurücksetzen und ersetzen die täglichen Backups nicht.
Weitere Ereignisse desselben Spielticks können noch auftreten.

## Installation / Update

Direkte Updates vom privaten GitHub-Repository sind in [UPDATES.md](UPDATES.md)
beschrieben. Nach einmaliger Einrichtung reicht `~/.local/bin/factorio-mod-update`.
Lizenz: [MIT](../LICENSE), Copyright (c) 2026 dermalla.

Der Installer enthält die ZIP bereits; Download-Zugangsdaten sind nicht nötig.

1. `install-factory-night-watch.sh` auf den Server nach `/home/<benutzer>/` übertragen.
2. `sudo bash /home/<benutzer>/install-factory-night-watch.sh` starten.
3. Er sperrt parallele Backups, stoppt Factorio, legt einen vollständigen Installations-Rücksetzpunkt
   mit neuestem Spielstand/Mods/Konfiguration an, ersetzt alte Mod-ZIPs, setzt `auto_pause=false`
   und prüft den Serverstart. Andere Container werden nicht bearbeitet.
4. Auf ALLEN Clients die alte ZIP aus dem Mods-Ordner entfernen und die unveränderte neue
   `factory-night-watch_0.3.3.zip` nach `%APPDATA%\Factorio\mods` kopieren. Nicht entpacken.
   Factorio neu starten. Alle Spieler und der Server brauchen dieselbe Version.

Alternativer Serverpfad: `sudo bash ./install-factory-night-watch.sh /pfad/zum/factorio-projekt`.
Standard: `/home/<sudo-benutzer>/docker/factorio`. Der Installer verwendet den bestehenden
Container `factorio` und `compose.yaml` sowie dieselbe Sperre wie die täglichen Backups.
Installations-Rücksetzpunkte liegen in `backups/night-watch-install` und werden nicht durch die
reguläre Backup-Aufbewahrung gelöscht. Installer-Fehler stellen vorherige Mod-/Konfigurationsdateien
wieder her; bei vollständigem Spielstand-Rollback den Rücksetzpunkt verwenden.

Upgrades innerhalb der Mod-ID behalten Einstellungen, Offline-Uhr und Alarm. Die entfernten
Hub-Einstellungen werden von Factorio verworfen. Ein vorhandener Alarm aus einer alten Version
bleibt bis zur Bestätigung erhalten. Blueprint Sandboxes bleibt separat installiert.
Diese private Version ist nicht im Modportal und wird von dort nicht automatisch synchronisiert.

### Befehle

- `/fnw-gui`: Fenster öffnen (alle Spieler).
- `/fnw-status`: Status (alle Spieler).
- `/fnw-resume`: Schutzpause bestätigen (Admin/Serverkonsole).
- `/fnw-test-pause`: Sofortige Testpause samt Speicherung (Admin/Serverkonsole).
- `/fnw-set max-offline-hours 168`: Zeitlimit (Admin/Serverkonsole), 0 = unbegrenzt.
- `/fnw-set research-pause false`: Forschungsregel abschalten.
- `/fnw-set enabled false`: Bei leerem Server sofort pausieren.
- `/fnw-set enabled true`: Geschützt weiterlaufen.

Keine Lua-Konsolenbefehle nötig. Lesbare Integration für andere Mods:
`remote.call("factory-night-watch", "status")`. Keine schreibende Remote-Schnittstelle.

### Entfernen

Bestehenden Alarm quittieren, speichern, Server stoppen. In `config/server-settings.json`
`auto_pause=true` setzen, `factory-night-watch` in der Modliste deaktivieren, Server starten.
Auf Clients ebenfalls deaktivieren. Die Mod fügt ein reines Auswahlwerkzeug hinzu, keine baubaren
Gebäude. Beim vollständigen Spielstand-Rollback geht späterer Spielfortschritt verloren.

## English quick guide

Open the radar shortcut at the bottom right, or run `/fnw-gui`. All players can view status;
only admins can change server-wide settings, test a pause, or acknowledge alarms.

Overview selects either protected offline running (default) or immediate empty-server pause.
Ordinary empty-server pauses resume on join; safety alarms always require acknowledgement.
Rules cover structure destruction, an empty research queue (default 5 minutes), and the offline
time limit (default 7 simulation days; uncheck to disable). Advanced contains exceptions, three
rotating emergency saves, optional circuit conditions and compatibility settings.

For a circuit rule, select a wired electric pole with the selection tool, choose red or green,
a signal including quality, comparison, threshold and continuous delay. Save the draft.
Rules run once per simulation second and only trigger while no players are connected. A false
condition resets its delay. A signal absent from a connected network reads 0; a missing pole
or selected wire network triggers an offline safety pause. Complex logic belongs in combinators.
Multiple rules act as OR: any enabled rule may pause the entire world. Clearing a signal does not
release an existing alarm. Admins use the GUI or `/fnw-resume` after fixing the cause.

All durations use simulation time. Offline timers, circuit rules and alarms persist in saves.
Synthetic sandbox surfaces are excluded. The GUI, settings and runtime messages have German and
English translations, selected using the client's Factorio language.

## Validation and limits

See TESTS.txt. Engine behavior is tested with Factorio headless 2.1.23; GUI interaction logic uses
API-checked mocks. Native Windows GUI rendering and multiple simultaneous real clients still need
an in-game check. No protection against OS failure or direct entity deletion by other mods.
Existing autosaves and daily backups remain necessary.

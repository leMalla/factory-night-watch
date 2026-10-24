# Frequently asked questions

## Will this stop biters before anything is damaged?

No. Structure-loss protection reacts after a destruction event. The world then
pauses so an admin can inspect the situation. It does not undo the event or make
entities invulnerable.

## Does the game resume when a player joins?

A normal empty-server pause resumes on join. A safety alarm requires an admin
to acknowledge it through the GUI or `/fnw-resume`, so the cause can be checked
before production continues.

## Does research pause when science packs run out?

No. Research protection waits until all monitored forces have neither selected
nor queued research. A selected research project waiting for science is still
considered active. The default idle delay is five simulation minutes.

## Are the seven days real days?

They are simulation days. At 60 UPS and normal game speed they pass at the same
rate as real time. Pauses and server downtime do not count; lower UPS or a changed
game speed affect how quickly the limit is reached in real time.

## What happens if a circuit signal disappears?

An absent signal in an intact selected network has value zero, as in normal
circuit logic. Removing the selected source entity or its chosen connection instead
causes an offline safety pause for an enabled rule. Disable the rule or repair
its source before acknowledging the alarm.

## Can I select a network between a chest and an inserter?

Yes. Any connected circuit entity can serve as the network access point. Select
one entity or drag an area around several. The same network is listed once;
copper power connections are ignored. A single network is selected directly.
If several networks are found, explicitly choose red/green and input/output in
the dropdown. A combinator can expose four distinct networks.

The mod stores the exact entity and connector, not only the displayed network
ID. Existing pole-based rules keep their original red/green connection. Source
coordinates remain saved for alarm-location viewing.

## Can I inspect an alarm on another planet or platform?

Yes. **View alarm location** opens remote view at the recorded position while
keeping the safety pause active. It does not teleport your character. Time-limit,
research and manual test alarms have no specific map location, so they do not
offer a location button.

## Does it work without Space Age or in single-player?

Both base-game-only and Space Age configurations are tested on Factorio 2.1.23.
Offline safety rules are designed for multiplayer. A connected AFK player still
counts as online.

## Can I add it to an existing save?

Yes. Back up the save first, install the same version on server and clients, and
review the settings. On a dedicated server, set `auto_pause=false` for protected
offline running. The mod stores its timers, alarms and circuit rules in the save.

## Does it replace normal backups?

No. Emergency saves are requested after an alarm, using three rotating slots.
They do not restore an earlier state or protect against a failed disk or server.
Keep a normal backup routine.

## Is this an AI-controlled mod?

No. AI-assisted coding tools were used during development. The installed mod
runs ordinary Factorio scripts and does not connect to an AI service or require
an AI account. The optional external server updater connects to GitHub to download
code; it is separate from the in-game mod.

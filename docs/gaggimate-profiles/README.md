# GaggiMate Descale Profiles

These files are one-profile-per-file imports for the GaggiMate profile page.

- `descale.json` runs a supervised steam-wand-only descale cycle.
- `descale-flush.json` runs a supervised clean-water steam-wand-only flush.

## Safety Notes

- Keep the steam valve open before any pump phase starts.
- Do not run these through the group head.
- Do not leave the machine unattended.
- Stop the profile if the tank runs empty, the output container fills, or the pump sounds dry.
- Run the flush profile with clean water until the descale smell/taste is gone.

The profiles cannot detect tank level, container level, or steam valve position.
The phase names are written as prompts so the touchscreen gives useful reminders.

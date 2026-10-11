# CASE media library consolidation

This directory contains **planning tools only** for consolidating the existing movie libraries. The inventory reads configured source roots and writes reports outside them. The migration planner reads those reports and proposes destinations. Neither script moves, renames, copies or deletes media.

Production Radarr, Sonarr, Bazarr, Seerr, Prowlarr, qBittorrent, Plex and Docker configuration are deliberately outside this phase.

## Proposed library layout

```text
D:\Media Centre\Movies\
  1080p\
    Movie Title (2024)\
      Movie Title (2024).mkv
      Movie Title (2024).en.srt
  2160p\
    Movie Title (2024)\
      Movie Title (2024).mkv
  3D\
    Movie Title (2024) {edition-3D SBS}\
      Movie Title (2024) {edition-3D SBS}.mkv
D:\Media Centre\TV Shows\
  ... unchanged ...
```

Keeping 1080p and 2160p in separate physical roots preserves an uncomplicated future split between the two Radarr instances. Plex can combine equivalent cuts as versions. A materially different cut, including 3D, should be represented as an edition using Plex's `{edition-...}` naming.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7.
- `ffprobe` available on `PATH` for rich stream metadata. It is supplied by FFmpeg.
- Enough free space in the report directory for JSON and CSV reports. The scanner does not copy media.
- The actual current roots for standard, 4K and 3D movies. Do not guess the 3D path.

## Phase 1: read-only inventory

1. Copy `inventory.config.example.json` to untracked `inventory.config.json`.
2. Replace all three source roots with their actual locations.
3. Confirm `outputDirectory` is outside every media root.
4. Confirm the proposed target root and quality folder names.
5. Run the inventory from PowerShell:

```powershell
cd D:\path\to\case-home-assistant\deploy\media-automation\library-consolidation
.\scripts\New-MediaInventory.ps1 -ConfigPath .\inventory.config.json
```

Use `-SkipFfprobe` only for script testing. It falls back to collection hints and therefore creates less reliable classifications.

The example configuration bounds every probe so one malformed movie cannot stop the inventory:

- `ffprobeTimeoutSeconds`: hard wall-clock limit per file; defaults to 60 seconds.
- `ffprobeProbeSizeBytes`: maximum data considered while probing streams; defaults to 100 MiB.
- `ffprobeAnalyzeDurationMicroseconds`: bounded stream analysis duration; defaults to 30 seconds.
- `ffprobeErrorSummaryLines`: unique stderr lines retained in reports; defaults to 8 and never writes the complete noisy stderr stream.

Both stdout and stderr are drained concurrently to prevent a corrupt file from filling an error pipe and deadlocking the scan. Timeouts, failed probes and malformed stream signatures are placed in manual review, including a compact stderr summary. The original media is never opened for writing or repaired. Scanning prints `[current/total]` and the current filename so a slow item is visible.

The run creates a timestamped directory containing:

- `media-inventory.json`: complete machine-readable inventory, stream metadata and sidecars.
- `media-inventory.csv`: compact spreadsheet-friendly inventory.
- `media-inventory-summary.md`: collection, size, duplicate and version overview.
- `manual-review.csv` and `manual-review.md`: ambiguous names, unmatched metadata, orphan subtitles and other exceptions.

By default, duplicate candidates are identified by normalized title/year and exact size, but are **not** declared true duplicates. Set `hashDuplicateCandidates` to `true`, or pass `-HashDuplicateCandidates`, to SHA-256 only those narrow candidates. A matching hash confirms identical bytes; a different hash confirms they are distinct files.

## Phase 2: proposed migration plan

After reviewing the inventory, generate a proposal:

```powershell
$inventory = Get-ChildItem D:\Downloads\Media-Inventory\inventory-*\media-inventory.json |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

.\scripts\New-MediaMigrationPlan.ps1 `
  -InventoryPath $inventory.FullName `
  -ConfigPath .\inventory.config.json
```

This creates JSON, CSV, Markdown and a manual-review queue. Every source receives a proposed destination, classification, action and confidence. Colliding target paths are marked `Hold`; the planner never overwrites or resolves them automatically.

There is intentionally no migration executor yet. Build it only after the inventory and plan have been reviewed and approved. Its minimum design requirements are:

- Dry-run is the default and execution requires an explicit approval switch.
- Append-only operation log with source, destination, sizes, hashes and outcome.
- Restartable and idempotent: completed operations are recognized, not repeated.
- Preflight free-space checks and source/destination filesystem checks.
- Copy, verify size and hash, then remove source only after successful verification.
- Never overwrite an existing file; collisions stop in a manual queue.
- Move the video and its approved subtitle sidecars as one logical operation.
- Preserve source until verification and retain a rollback manifest.
- Do not delete duplicates automatically, even when hashes match.

## Naming and subtitles

Use `Movie Title (Year)` for the folder and video stem. Use `{edition-Edition Name}` for genuinely different cuts such as Director's Cut, theatrical, IMAX or 3D. Keep same-cut 1080p and 2160p files as versions, not editions.

External subtitle names must begin with the exact video stem:

```text
Movie Title (2024).en.srt
Movie Title (2024).en.forced.srt
Movie Title (2024).en.sdh.srt
```

The planner carries identified language, forced and SDH markers into proposed names. Unidentified or orphan subtitles stay in manual review. No subtitle is discarded.

Plex notes:

- Multiple editions require Plex Pass for the server administrator.
- Plex can automatically or manually select among multiple versions of the same cut.
- Renaming an existing file to introduce an edition may create a new Plex item and lose item-specific customizations. Where preserving an existing item matters, set its edition in Plex before or during the controlled pilot.
- Text subtitles such as SRT are the least likely to force transcoding. Image formats such as PGS or VobSub can require transcoding on some clients.

References: [movie naming](https://support.plex.tv/articles/naming-and-organizing-your-movie-media-files/), [multiple editions](https://support.plex.tv/articles/multiple-editions/), [local subtitles](https://support.plex.tv/articles/200471133-adding-local-subtitles-to-your-media/).

## Phase 3: Plex pilot

Do not start with the full library. Choose a representative, approved set:

- One ordinary 1080p movie with an external English subtitle.
- One ordinary 2160p movie.
- One title present in both 1080p and 2160p.
- One HDR or Dolby Vision title.
- One 3D title.
- One genuine alternate edition, if present.

Before the pilot, back up the Plex database and disable automatic emptying of trash. Stop Plex before filesystem moves. Add the new target locations while retaining the old locations, scan, verify matches, posters, watch state, versions, editions, subtitles and playback, and only then remove the old location. Empty trash only after final verification. See Plex's [moving media guide](https://support.plex.tv/articles/201154537-move-media-content-to-a-new-location/) and [scan versus refresh guidance](https://support.plex.tv/articles/200289306-scanning-vs-refreshing-a-library/).

Pilot acceptance checks:

- Each movie matches the correct title and year.
- 1080p and 2160p of the same cut appear as selectable versions.
- 3D and other cuts appear as clearly named editions.
- Existing watched status and metadata remain acceptable.
- English subtitles are discoverable and correctly labelled.
- Direct play/transcode behavior is understood on the main clients.
- Radarr has not renamed, moved or imported any existing production media.

## Phase 4: production cutover checklist

This phase is tracking only until separately approved:

- Approve every manual-review and collision decision.
- Freeze library writers and active imports for the cutover window.
- Capture fresh Plex and application backups.
- Record source and target free space.
- Run a final inventory and diff it against the approved plan.
- Execute approved batches, verify each batch, then scan Plex.
- Reconcile Plex versions/editions, Bazarr subtitle status and Radarr ownership.
- Keep legacy roots mounted read-only until sign-off.
- Remove old Plex locations only after full validation.
- Retain operation and rollback manifests.

Planned application changes after approval:

| Component | Proposed production change | Safety boundary / validation |
| --- | --- | --- |
| Radarr | Replace `/media/test` with one writable mount for `D:\Media Centre\Movies\1080p`; adopt that root; review naming, quality upgrades and size limits; validate its completed-download category. | It must not have write access to 2160p, 3D or TV roots. Import a pilot title before enabling automatic searching. |
| Radarr 4K | Add one writable mount for `D:\Media Centre\Movies\2160p`; use a distinct `radarr-4k` qBittorrent category; review 4K, HDR and size rules. | It must not overlap the standard Radarr root. Confirm it acquires an additional version rather than replacing 1080p unexpectedly. |
| 3D collection | Keep the 3D root outside automatic Radarr ownership unless a separately tested 3D workflow is approved. | Preserve all 3D files and identify them as Plex editions. No automatic upgrade or deletion. |
| Sonarr | Confirm one writable TV root, naming convention, quality profile and dedicated qBittorrent category. | Existing TV remains protected until an import-only pilot proves matching and episode layout. |
| Bazarr | Connect both Radarr instances and Sonarr; select English as required; configure forced/SDH preferences and approved subtitle providers. | Grant write access only to the roots whose subtitles it manages. Verify it does not replace preferred existing subtitles unexpectedly. |
| Seerr | Map normal requests to standard Radarr and explicit 4K requests to Radarr 4K; review permissions and defaults. | The household default remains 1080p unless 4K is intentionally selected. Test requests must use pilot titles. |
| Prowlarr | Keep indexer synchronization to Radarr, Radarr 4K and Sonarr; review application categories and sync behavior. | Do not broaden filesystem or VPN access. Validate searches independently before enabling automatic grabs. |
| qBittorrent / Gluetun | Retain the separate VPN stack and kill switch; add or confirm distinct categories and shared completed-download paths required by each manager. | No Docker network redesign, host peer-port publishing, router forwarding or VPN bypass. Re-run the existing VPN and kill-switch tests after category/path changes. |
| Plex | Add 1080p, 2160p and 3D as three locations in one Movies library while old locations remain during validation. | Back up Plex first, disable automatic trash emptying, verify matches and history, then remove old locations only after sign-off. |

No row in this table is an instruction to change production now. Each change needs a separately approved implementation and rollback step.

## Self-test

The fixture test creates a disposable library beneath the operating system temp directory, inventories it, creates a plan and verifies every source hash, length, path and timestamp is unchanged:

```powershell
.\scripts\Test-MediaPlanning.ps1
```

It cleans up only its own uniquely named temporary fixture.

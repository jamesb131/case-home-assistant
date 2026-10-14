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
    Movie Title (2024)\
      Movie Title (2024).mkv
D:\Media Centre\TV Shows\
  ... unchanged ...
```

Keeping 1080p and 2160p in separate physical roots preserves an uncomplicated future split between the two Radarr instances. Plex can combine equivalent cuts as versions. The 3D collection stays physically separate. Existing edition labels are preserved, but the planner does not invent a 3D edition or SBS label from the user's unverified layout assumption.

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

## Phase 1b: read-only TMDB enrichment

The metadata enrichment script reads an existing `media-inventory.json`; it does not rescan, probe or open the movie files. It searches TMDB, assigns confirmed IDs only when conservative matching rules pass, and writes a new timestamped report directory outside the media collection.

Create a TMDB account, request API access in the account settings, and obtain the **API Read Access Token**. TMDB documents the application process and Bearer-token authentication in its [getting started](https://developer.themoviedb.org/docs/getting-started) and [authentication](https://developer.themoviedb.org/docs/authentication-application) guides. Keep the token in the current process environment only; do not add it to a repository file.

Run the offline safety tests first:

```powershell
cd D:\path\to\case-home-assistant\deploy\media-automation\library-consolidation
.\scripts\Test-MediaPlanning.ps1
.\scripts\Test-MetadataEnrichment.ps1
```

Then enrich the newest real inventory:

```powershell
$secureTmdbToken = Read-Host "TMDB API read token" -AsSecureString
$tmdbCredential = New-Object System.Management.Automation.PSCredential("tmdb", $secureTmdbToken)
$env:TMDB_READ_TOKEN = $tmdbCredential.GetNetworkCredential().Password
Remove-Variable secureTmdbToken, tmdbCredential

$inventory = Get-ChildItem D:\Downloads\Media-Inventory\inventory-*\media-inventory.json |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

.\scripts\New-EnrichedMediaInventory.ps1 `
  -InventoryPath $inventory.FullName `
  -OutputDirectory D:\Downloads\Media-Inventory `
  -CacheDirectory D:\Downloads\Media-Inventory\tmdb-cache
```

The token is never written to the reports or cache. Search and detail responses are cached by request so reruns do not repeatedly call TMDB. Requests are rate-limited and retried; exhausted network failures are recorded as `ApiError` review items instead of aborting the rest of the inventory.

Each run creates `metadata-enrichment-<timestamp>` with:

- `enriched-media-inventory.json` and `.csv`: original paths/titles plus status, canonical metadata, scores and alternatives.
- `metadata-matching-summary.md`: run counts and matching policy.
- `metadata-manual-review.csv` and `.md`: ambiguous, unmatched, API-error and uncertain-3D items.
- `cross-version-groups.csv`: confirmed TMDB groups and their 1080p, 2160p, 3D and edition attributes.
- `metadata-overrides.template.csv`: editable decisions for the review queue.

`HighConfidence` means the title/year evidence and candidate margin met the conservative auto-confirmation threshold. `Ambiguous` never receives a confirmed TMDB ID, even when one result ranks first. Conflicting years are strongly penalized. Cross-version grouping uses only confirmed IDs; it preserves existing cut/edition labels and never calls two files identical unless the earlier inventory contains hash evidence.

To resolve review items, copy the generated template to a stable untracked file, then edit `Decision` to `Confirm`, `Unmatched` or `Ignore`. A `Confirm` row requires the chosen numeric TMDB movie ID; title and year may be left blank and will be loaded from TMDB.

```powershell
Copy-Item `
  D:\Downloads\Media-Inventory\metadata-enrichment-<timestamp>\metadata-overrides.template.csv `
  D:\Downloads\Media-Inventory\metadata-overrides.csv

.\scripts\New-EnrichedMediaInventory.ps1 `
  -InventoryPath $inventory.FullName `
  -OutputDirectory D:\Downloads\Media-Inventory `
  -CacheDirectory D:\Downloads\Media-Inventory\tmdb-cache `
  -OverridesPath D:\Downloads\Media-Inventory\metadata-overrides.csv
```

After the enrichment and any override reruns are complete, remove the token from the current process with `Remove-Item Env:TMDB_READ_TOKEN`.

Review all `Ambiguous`, `Unmatched`, `ApiError` and uncertain-3D rows before using the enriched inventory for later planning. The script does not invent 3D layouts or Plex edition labels. This phase does not rename, move, delete, download or repair media and does not modify Plex, Radarr, Bazarr or any other service.

## Phase 1c: read-only Plex reconciliation

Plex reconciliation treats an existing Plex movie match as the preferred identity only when a Plex media part maps uniquely to an inventory file by normalized absolute path. Titles never establish identity. This lets a path-linked Plex TMDB ID resolve an item that filename enrichment marked ambiguous while keeping duplicate mappings and genuine conflicts visible. Plex explains how to retrieve a local server token in [Finding an authentication token](https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/).

The script uses only Plex `GET` requests. It discovers every movie section, reads each section independently in pages with `includeGuids=1`, and requests individual item metadata when the section response lacks external IDs or media parts. Pagination is sent as Plex container query parameters, matching the server's native API. Plex responses are read as raw text and passed to a case-sensitive JSON parser because Plex can legally return both `guid` and `Guid`, which Windows PowerShell 5.1's `ConvertFrom-Json` rejects. Both properties and all nested media/part metadata are retained. Every section is checked against Plex's reported `totalSize`; repeated pages, incorrect offsets, truncated responses and early empty pages stop the run before a reconciliation report can be produced. Plex documents token headers, paths and container pagination in the [Plex Media Server API](https://developer.plex.tv/pms/). IMDb-only Plex matches are resolved with TMDB's read-only [`/find` workflow](https://developer.themoviedb.org/docs/finding-data), using the same cache directory as Phase 1b.

1. Copy the example configuration to the ignored local filename:

```powershell
Copy-Item .\plex-reconciliation.config.example.json .\plex-reconciliation.config.json
```

2. Set `plexBaseUrl` to the local Plex server URL and confirm the output/cache locations remain outside every media root.
3. Configure `pathMappings`. `plexPrefix` is the prefix Plex reports; `inventoryPrefix` is the equivalent Windows inventory prefix. Native Windows Plex paths can use an identity mapping. A containerized Plex example would be:

```json
{
  "plexPrefix": "/movies",
  "inventoryPrefix": "D:\\Media Centre\\Movies"
}
```

4. Run the offline fixture test:

```powershell
.\scripts\Test-PlexMetadataReconciliation.ps1
```

5. Put the Plex token and TMDB API Read Access Token into the current PowerShell process without echoing them:

```powershell
$securePlexToken = Read-Host "Plex token" -AsSecureString
$plexCredential = New-Object System.Management.Automation.PSCredential("plex", $securePlexToken)
$env:PLEX_TOKEN = $plexCredential.GetNetworkCredential().Password
Remove-Variable securePlexToken, plexCredential

$secureTmdbToken = Read-Host "TMDB API read token" -AsSecureString
$tmdbCredential = New-Object System.Management.Automation.PSCredential("tmdb", $secureTmdbToken)
$env:TMDB_READ_TOKEN = $tmdbCredential.GetNetworkCredential().Password
Remove-Variable secureTmdbToken, tmdbCredential
```

6. Verify Plex enumeration before doing any TMDB work or creating reports:

```powershell
.\scripts\New-PlexReconciledInventory.ps1 `
  -ConfigPath .\plex-reconciliation.config.json `
  -PlexEnumerationOnly
```

This diagnostic logs each section, request offset, requested page size, HTTP status, Plex-reported total, parsed count and any response-shape skip reason. It never prints the token or authenticated URL. It must finish with every expected movie library and matching reported/retrieved totals; an unknown total, empty non-empty library, repeated page or truncated response terminates the run. The diagnostic does not require an enriched inventory, call TMDB or create reconciliation reports.

7. Reconcile the newest enriched inventory:

```powershell
$enrichedInventory = Get-ChildItem D:\Downloads\Media-Inventory\metadata-enrichment-*\enriched-media-inventory.json |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

.\scripts\New-PlexReconciledInventory.ps1 `
  -EnrichedInventoryPath $enrichedInventory.FullName `
  -ConfigPath .\plex-reconciliation.config.json

Remove-Item Env:PLEX_TOKEN
Remove-Item Env:TMDB_READ_TOKEN
```

Each full reconciliation run creates `plex-reconciliation-<timestamp>` containing:

- `plex-reconciled-inventory.json` and `.csv`: reconciled TMDB identity, source, Plex identifiers, library, rating key and both original paths.
- `plex-reconciliation-summary.md`: counts resolved through Plex TMDB, Plex IMDb, prior enrichment and unresolved items, plus per-library Plex-reported records, records retrieved, media parts and inventory paths matched.
- `plex-reconciliation-review.csv`: exceptions only, including conflicts, duplicate path mappings, missing IDs, unresolved inventory and Plex parts absent from the inventory.
- `plex-cross-version-groups.csv`: groups based on reconciled TMDB IDs while preserving 1080p, 2160p and 3D classifications.

Identification sources are `PlexTMDB`, `PlexIMDb`, `TMDBEnrichment` and `Unresolved`. A unique path-linked Plex identity is authoritative even when it conflicts with the prior filename result, but the conflict remains in the exception report. Multiple Plex rating keys for one file are never allowed to override the previous identity. A 3D item remains a 3D variant; reconciliation does not infer that it is a separate Plex edition or cut.

Before reviewing reconciliation results, confirm the library-enumeration table shows every expected movie section and that `Plex reported` equals `Records retrieved` for each one. The JSON output includes the same data in `LibraryDiagnostics`, along with the total `InventoryFilesMatchedToPlex`. A mismatch is a failed run, not a warning, so partial Plex retrieval cannot silently inflate the manual-review queue.

The Plex and TMDB tokens are sent only as request headers and are never written to output or cache files. Do not place a token in `plexBaseUrl`. This phase performs no media operations, Plex metadata edits, scans, downloads or changes to Radarr, Sonarr, Bazarr, Docker or any other service.

## Phase 2: reconciled migration plan

The reconciled planner consumes `plex-reconciled-inventory.json`; it does not repeat filename matching. Confirmed TMDB title, year and ID determine the proposed movie folder. Every input video receives a `Ready`, `Review` or `Blocked` row, and associated subtitle destinations remain nested in the JSON manifest. The planner reads source metadata and existence only. It never moves, copies, renames or deletes files and never calls Plex, Radarr or Docker.

1. Copy the local planning files:

```powershell
Copy-Item .\reconciled-migration.config.example.json .\reconciled-migration.config.json
Copy-Item .\migration-overrides.example.csv .\migration-overrides.csv
Copy-Item .\migration-exclusions.example.csv .\migration-exclusions.csv
```

2. Confirm `targetMoviesRoot` is `D:\Media Centre\Movies`, output remains outside all media roots, and set the override row's `SourcePath` to the exact existing 3D `Toy Story 3D.mkv` path. That exact source alone is assigned **Toy Story (1995), TMDB 862**. The standard Toy Story 3 record is untouched. Confirm `migration-exclusions.csv` contains the exact source `D:\Media Centre\Movies\01 - Blackadder’s Christmas Carol.avi`; this row holds that file in place for later replacement.
3. Run the offline planning test:

```powershell
.\scripts\Test-ReconciledMigrationPlanning.ps1
```

4. Plan against the latest successful Plex reconciliation:

```powershell
$reconciliation = Get-ChildItem D:\Downloads\Media-Inventory\plex-reconciliation-*\plex-reconciled-inventory.json |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

$plexReview = Join-Path $reconciliation.Directory.FullName 'plex-reconciliation-review.csv'

.\scripts\New-ReconciledMigrationPlan.ps1 `
  -ReconciledInventoryPath $reconciliation.FullName `
  -ConfigPath .\reconciled-migration.config.json `
  -OverridesPath .\migration-overrides.csv `
  -ExclusionsPath .\migration-exclusions.csv `
  -PlexReviewPath $plexReview
```

The source override and exclusion are mandatory once supplied: an unmatched or duplicate exact path terminates planning, and one path cannot be both overridden and excluded. An exclusion requires an audit reason, becomes `Blocked`/`Hold`, and is omitted from the future operation set without changing the source. `PlexReviewPath` lets the planner compare unmatched Plex parts with inventory paths using ordinal, NFC, NFD and punctuation-normalized forms. CSV input is explicitly read as UTF-8 so the Blackadder’s Christmas Carol path can be assessed without losing apostrophes or other Unicode characters. The manifest records the exclusion CSV SHA-256; subsequent dry-run approval independently fingerprints the regenerated manifest and excluded-file evidence.

For the currently approved scope, confirm the regenerated plan before dry-run:

```powershell
$plan = Get-ChildItem D:\Downloads\Media-Inventory\reconciled-migration-plan-*\migration-manifest.json |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

$planData = Get-Content -LiteralPath $plan.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
$planData.ReadyCount
$planData.ExceptionCount
@($planData.Items | Where-Object ExplicitlyExcluded | Select-Object SourcePath, Status, ProposedAction, ExclusionReason)
```

The expected values are 508 Ready and 15 exceptions. The sole explicit exclusion must be the exact Blackadder source path and must report `Blocked` and `Hold`.

Each timestamped `reconciled-migration-plan-*` directory contains:

- `migration-manifest.json` and `.csv`: all source videos, authoritative identity, Plex details, target class/path, subtitle plan, status, explicit-exclusion evidence, historical inventory warnings, informational warnings, review reasons and blocked reasons.
- `migration-exceptions.csv` and `.md`: only `Review` and `Blocked` decisions.
- `cross-version-groups.csv`: 1080p, 2160p and 3D variants grouped by reconciled TMDB ID, with duplicate-version and multiple-cut flags.
- `destination-collisions.csv` and `.md`: evidence for every source targeting the same case-insensitive destination. Participants remain blocked; the planner never merges, overwrites, arbitrarily renames or changes identity.
- `media-health.csv` and `.md`: ffprobe, malformed-stream and related media-health observations. These remain visible without automatically changing migration status.
- `plex-path-analysis.csv`: exact and Unicode-normalized Plex/inventory path comparisons, including unmatched filename candidates.
- `preflight.json` and `.md`: source presence, existing destinations, source size and observed target-drive capacity.
- `rollback-manifest.json` and `.csv`: proposed reverse paths, expected size and existing hash evidence. This is guidance, not an executable rollback.
- `plex-transition-plan.md`: staged Plex location changes, pilot validation, metadata/history preservation and rollback guidance.

The 3D rows record the user-reported “probably SBS” statement as an assumption only. Unresolved identities are blocked. Plex/TMDB conflicts, measured-resolution/source-collection mismatches, duplicate versions and multiple cuts remain explicit review items. Destination paths are compared case-insensitively, including subtitle paths, and any collision or existing destination blocks the affected row.

Historical discovery warnings such as a missing year in the original filename, a root-level file, several videos sharing the old collection root, or a quality classification consistent with the measured resolution are informational once reconciliation provides a confirmed TMDB identity and canonical year. They remain in the manifest for traceability but do not hold an otherwise unambiguous plan. A validated exact source-path override similarly resolves the identity conflict it addresses while retaining the original disagreement as an informational audit entry.

Phase 2 remains planning-only; generating its reports never changes media.

## Phase 3: controlled migration execution

Phase 3 consumes `migration-manifest.json` exactly as written. It selects only rows whose status is `Ready`, uses their existing destination paths, and leaves every `Review` and `Blocked` source untouched. It does not recalculate titles, years, identities, classifications or paths.

The workflow is deliberately split into four commands:

- `Invoke-ReconciledMigration.ps1` defaults to a read-only dry run. `-Execute` or `-Resume` is required to move approved files.
- `Test-ReconciledMigrationResult.ps1` verifies destination files, source absence, journal completion and continued presence of excluded source files.
- `Undo-ReconciledMigration.ps1` defaults to a rollback dry run. Its `-Execute` mode restores only journal-confirmed operations in reverse order.
- `Test-MigrationExecutor.ps1` exercises collisions, source changes, interrupted sidecar moves, resume, excluded files, verification and rollback beneath a disposable temp directory.

No command removes empty source folders or changes Plex, Radarr, Bazarr, Docker, qBittorrent or VPN configuration. Same-volume file moves are used for individual files. A movie plus its sidecars is **not** an atomic multi-file operation; sidecars are moved first and the video last, with each operation durably journaled.

### Mandatory Plex preparation

Do not execute until every item below has been completed and independently checked:

1. Locate the native Windows Plex Media Server application-data directory. Confirm the proposed backup contains `Plug-in Support\Databases\com.plexapp.plugins.library.db`, `Metadata`, and `Media`.
2. Treat the 10 October 2026 backup as unverified until its contents and readability have been checked. Take a fresh full application-data backup while Plex is completely stopped.
3. Record the original paths, section names and settings for **Movies**, **Movies 4K**, and **Movies 3D**.
4. In Plex, disable **Empty trash automatically after every scan**.
5. Temporarily disable automatic library scans, scheduled scans, partial scans and automatic metadata activity that could race the move.
6. Stop Plex Media Server completely and confirm its server/scanner processes have exited.
7. Stop Radarr, Radarr 4K, Bazarr and any downloader, import script or other process able to write to the movie or download folders.
8. Keep the backup, migration approval bundle and operation journal on reliable storage. A Plex application-data backup protects Plex metadata; it does **not** back up the movie files themselves.

The executor blocks if it can detect Plex running. Process detection and backup consistency cannot be guaranteed on every Windows installation, so execution also requires explicit `-PlexBackupVerified`, `-PlexStoppedAcknowledged`, and `-MediaWritersStoppedAcknowledged` switches. These are acknowledgements, not automated proof.

### Dry run and readiness gate

From `deploy\media-automation\library-consolidation` on the Windows PC:

```powershell
$plan = Get-ChildItem D:\Downloads\Media-Inventory\reconciled-migration-plan-*\migration-manifest.json |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

$executionRoot = Join-Path 'D:\Downloads\Media-Inventory' ("migration-execution-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

$dryRun = .\scripts\Invoke-ReconciledMigration.ps1 `
  -ManifestPath $plan.FullName `
  -OutputDirectory $executionRoot

$dryRun
```

The dry run hashes the manifest and every media file, validates every Ready source, captures sidecar size/hash evidence, checks case-insensitive destination collisions, refuses existing destinations and cross-volume moves, and records size/hash evidence for all excluded files while keeping them outside the operation set. Depending on disk speed, hashing approximately 1.35 TiB may take a long time; do not interrupt it merely because progress is slow.

Review all of these before approving execution:

- `migration-dry-run.md` and `migration-dry-run.csv`
- `migration-preflight.csv` with no failed checks
- `migration-excluded-items.csv`, containing all 15 Review/Blocked items from the current plan, including the exact Blackadder exclusion
- `plex-library-transition-mapping.md` and `.csv`
- `migration-approval.json`, which must say `ApprovedForExecution: true`

The Plex transition report distinguishes moves within an existing library from moves crossing a library boundary. Any Ready `CrossLibraryBoundary` or `UnknownLibraryBoundary` row fails readiness and requires a separate handling decision. The executor will not assume Plex can preserve identity across libraries.

For the current approved scope, inspect the fresh approval evidence rather than editing it:

```powershell
$approval = Get-Content -LiteralPath $dryRun.ApprovalPath -Raw -Encoding UTF8 | ConvertFrom-Json
$approval | Select-Object ApprovedForExecution, ReadyItemCount, ExcludedItemCount, CrossLibraryReadyCount, UnknownLibraryReadyCount, ManifestSha256, ExcludedEvidenceDigest
```

Expected: `ApprovedForExecution=True`, `ReadyItemCount=508`, `ExcludedItemCount=15`, `CrossLibraryReadyCount=0`, and `UnknownLibraryReadyCount=0`. If any value differs, stop and review the generated reports; do not edit the approval file or hashes.

Execution is also refused if the manifest, excluded set, transition report or approved operation set changes after the dry run.

### Execute, resume and verify

After completing the Plex preparation checklist and reviewing a passing dry run:

```powershell
$approval = Join-Path $executionRoot 'migration-approval.json'
$journal = Join-Path $executionRoot 'migration-execution-journal.ndjson'

.\scripts\Invoke-ReconciledMigration.ps1 `
  -ManifestPath $plan.FullName `
  -Execute `
  -ApprovalPath $approval `
  -JournalPath $journal `
  -PlexBackupVerified `
  -PlexStoppedAcknowledged `
  -MediaWritersStoppedAcknowledged
```

If PowerShell or Windows is interrupted, do not rerun `-Execute`. Inspect the append-only journal, keep Plex and writers stopped, then resume the same approved operation set:

```powershell
.\scripts\Invoke-ReconciledMigration.ps1 `
  -ManifestPath $plan.FullName `
  -Resume `
  -ApprovalPath $approval `
  -JournalPath $journal `
  -PlexBackupVerified `
  -PlexStoppedAcknowledged `
  -MediaWritersStoppedAcknowledged
```

Resume accepts only two safe states: the approved source exists and destination does not, or the source is absent and the destination matches the approved evidence. Both-existing and both-missing states stop the run.

Run post-migration verification before starting Plex or changing any Plex path:

```powershell
.\scripts\Test-ReconciledMigrationResult.ps1 `
  -ManifestPath $plan.FullName `
  -ApprovalPath $approval `
  -JournalPath $journal `
  -OutputDirectory $executionRoot
```

Review `post-migration-verification.md`, `post-migration-verification.csv`, and `post-migration-excluded-verification.csv`. A PASS proves approved filesystem and journal state only; Plex metadata still needs manual validation.

Also retain `migration-execution-journal.ndjson` and `migration-execution-summary.md`. The journal is append-only and is the authoritative resume/rollback record; do not edit, truncate or recreate it.

### Phase A Plex transition

Do not consolidate libraries in Phase A. Retain all three libraries and every original configured location. With automatic trash emptying still disabled, add only:

- **Movies**: `D:\Media Centre\Movies\1080p`
- **Movies 4K**: `D:\Media Centre\Movies\2160p`
- **Movies 3D**: `D:\Media Centre\Movies\3D`

Start Plex and scan one existing library at a time. Validate matches, rating keys where observable, watched status, posters, collections, external IDs, versions, editions, subtitles and playback before moving to the next library. The 15 Review/Blocked files remain at their original paths and remain visible because the original locations are retained. Do not remove those locations or empty Plex trash while any excluded file remains there.

The 3D SBS classification remains a user-reported assumption. Do not create Plex edition labels from it without technical verification. Library consolidation is a later Phase B operation after the file migration and metadata behaviour have been accepted.

### Rollback and Plex recovery

First perform a rollback dry run:

```powershell
.\scripts\Undo-ReconciledMigration.ps1 `
  -ManifestPath $plan.FullName `
  -ApprovalPath $approval `
  -JournalPath $journal `
  -OutputDirectory $executionRoot
```

With Plex and media writers stopped, execute the rollback only after reviewing `rollback-preflight.csv` and `rollback-report.md`:

```powershell
.\scripts\Undo-ReconciledMigration.ps1 `
  -ManifestPath $plan.FullName `
  -ApprovalPath $approval `
  -JournalPath $journal `
  -Execute `
  -OutputDirectory $executionRoot `
  -PlexStoppedAcknowledged `
  -MediaWritersStoppedAcknowledged
```

If Plex treats moved files as deleted, creates duplicates, loses watched state/posters/collections, or groups versions incorrectly:

1. Stop Plex immediately.
2. Do not empty trash, remove old library locations or run further scans.
3. Stop Radarr, Bazarr and all other media writers.
4. Dry-run and then execute rollback for every journal-confirmed move.
5. If metadata remains damaged, restore the stopped-state Plex database and full application-data backup, including `Metadata` and `Media`.
6. Restart Plex with the original three libraries and original paths only.
7. Verify library counts, matches, watched history, posters, collections and playback before enabling scans or writers.

Rollback does not delete newly created empty target directories and does not touch Plex. A Plex backup cannot restore missing movie files; the media rollback journal is therefore essential.

## Legacy inventory-only planner

The earlier filename/inventory planner remains available for fixture compatibility, but it is not the production planning path now that Plex reconciliation exists:

```powershell
$inventory = Get-ChildItem D:\Downloads\Media-Inventory\inventory-*\media-inventory.json |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

.\scripts\New-MediaMigrationPlan.ps1 `
  -InventoryPath $inventory.FullName `
  -ConfigPath .\inventory.config.json
```

This creates JSON, CSV, Markdown and a manual-review queue. Every source receives a proposed destination, classification, action and confidence. Colliding target paths are marked `Hold`; the planner never overwrites or resolves them automatically.

The controlled executor does not accept this legacy inventory-only plan. It requires the authoritative reconciled manifest produced by `New-ReconciledMigrationPlan.ps1` and the Phase 3 dry-run approval workflow above.

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

## Manual Plex pilot after Phase A

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
- 3D remains in its dedicated location; no edition label is inferred from the unverified SBS assumption.
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

The fixture suites create disposable libraries beneath the operating-system temp directory. They cover inventory, matching, planning and the controlled executor lifecycle without touching production media:

```powershell
.\scripts\Test-MediaPlanning.ps1
.\scripts\Test-MetadataEnrichment.ps1
.\scripts\Test-PlexMetadataReconciliation.ps1
.\scripts\Test-ReconciledMigrationPlanning.ps1
.\scripts\Test-MigrationExecutor.ps1
```

Each test cleans up only its own uniquely named temporary fixture. The metadata, Plex reconciliation and reconciled migration suites use offline fixtures and do not require credentials or network access.

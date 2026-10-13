[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [switch]$DryRun,
    [switch]$Execute,
    [switch]$Resume,

    [string]$OutputDirectory,
    [string]$ApprovalPath,
    [string]$JournalPath,

    [switch]$PlexBackupVerified,
    [switch]$PlexStoppedAcknowledged,
    [switch]$MediaWritersStoppedAcknowledged,
    [switch]$FixtureMode
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'MigrationExecutor.Common.ps1')

$selectedModes = @()
if ($DryRun) { $selectedModes += 'DryRun' }
if ($Execute) { $selectedModes += 'Execute' }
if ($Resume) { $selectedModes += 'Resume' }
if (@($selectedModes).Count -gt 1) { throw 'Choose only one of -DryRun, -Execute or -Resume.' }
$mode = if ($Execute) { 'Execute' } elseif ($Resume) { 'Resume' } else { 'DryRun' }
$context = Read-MigrationManifest $ManifestPath
if ($FixtureMode) {
    $tempKey = Get-NormalizedMigrationPath ([IO.Path]::GetTempPath())
    if (-not (Get-NormalizedMigrationPath $context.Path).StartsWith($tempKey, [StringComparison]::OrdinalIgnoreCase)) { throw '-FixtureMode is restricted to manifests beneath the operating-system temp directory.' }
}

function New-TransitionRows {
    param([object[]]$Items)
    return @($Items | ForEach-Object {
        $status = "$(Get-MigrationProperty $_ 'Status' '')"
        $classification = "$(Get-MigrationProperty $_ 'Classification' '')"
        $sourceLibrary = "$(Get-MigrationProperty $_ 'PlexLibrary' '')".Trim()
        $targetLibrary = Get-ExpectedPlexLibrary $classification
        $boundary = if ($status -ne 'Ready') { 'ExcludedItemRemainsAtOriginalPath' }
            elseif (-not $sourceLibrary -or -not $targetLibrary) { 'UnknownLibraryBoundary' }
            elseif ([string]::Equals($sourceLibrary, $targetLibrary, [StringComparison]::OrdinalIgnoreCase)) { 'WithinExistingLibrary' }
            else { 'CrossLibraryBoundary' }
        [pscustomobject]@{
            InventoryId = Get-MigrationProperty $_ 'InventoryId'; Status = $status; SourcePath = Get-MigrationProperty $_ 'SourcePath'
            DestinationVideoPath = Get-MigrationProperty $_ 'DestinationVideoPath'; Classification = $classification
            ExistingPlexLibrary = $sourceLibrary; ExpectedPlexLibrary = $targetLibrary; TransitionType = $boundary
            PlexRatingKey = Get-MigrationProperty $_ 'PlexRatingKey'; TmdbMovieId = Get-MigrationProperty $_ 'TmdbMovieId'
        }
    })
}

function Test-OperationSet {
    param([object[]]$Operations, [bool]$AllowResumeState, [string]$TargetMoviesRoot, [bool]$UseCapturedHashEvidence = $false)
    $checks = [Collections.Generic.List[object]]::new()
    $destinationGroups = @($Operations | Group-Object { Get-NormalizedMigrationPath $_.DestinationPath } | Where-Object Count -gt 1)
    foreach ($group in $destinationGroups) {
        $checks.Add([pscustomobject]@{ Passed = $false; Check = 'DestinationCollision'; OperationId = ''; Detail = "Multiple approved operations target $($group.Group[0].DestinationPath)" })
    }
    $sourceGroups = @($Operations | Group-Object { Get-NormalizedMigrationPath $_.SourcePath } | Where-Object Count -gt 1)
    foreach ($group in $sourceGroups) {
        $checks.Add([pscustomobject]@{ Passed = $false; Check = 'DuplicateSource'; OperationId = ''; Detail = "Multiple approved operations use $($group.Group[0].SourcePath)" })
    }
    $index = 0
    foreach ($operation in $Operations) {
        $index++
        Write-Progress -Activity 'Migration preflight' -Status "$index / $(@($Operations).Count): $($operation.SourcePath)" -PercentComplete (($index / [math]::Max(1, @($Operations).Count)) * 100)
        $source = "$($operation.SourcePath)"
        $destination = "$($operation.DestinationPath)"
        if (-not $source -or -not $destination) {
            $checks.Add([pscustomobject]@{ Passed = $false; Check = 'PathsPresent'; OperationId = $operation.OperationId; Detail = 'Source or destination path is blank' })
            continue
        }
        if ((Get-NormalizedMigrationPath $source) -eq (Get-NormalizedMigrationPath $destination)) {
            $checks.Add([pscustomobject]@{ Passed = $false; Check = 'DistinctPaths'; OperationId = $operation.OperationId; Detail = 'Source and destination resolve to the same path' })
        }
        if (-not (Test-MigrationPathWithin -Path $destination -Root $TargetMoviesRoot)) {
            $checks.Add([pscustomobject]@{ Passed = $false; Check = 'DestinationBoundary'; OperationId = $operation.OperationId; Detail = "Destination is outside the manifest target movie root: $destination" })
        }
        $destinationAncestor = Split-Path -Parent $destination
        while ($destinationAncestor -and -not (Test-Path -LiteralPath $destinationAncestor)) { $destinationAncestor = Split-Path -Parent $destinationAncestor }
        if (-not $destinationAncestor -or -not (Test-Path -LiteralPath $destinationAncestor -PathType Container)) {
            $checks.Add([pscustomobject]@{ Passed = $false; Check = 'DestinationParent'; OperationId = $operation.OperationId; Detail = "No reachable destination parent exists for: $destination" })
        }
        if (-not (Test-SameMigrationVolume $source $destination)) {
            $checks.Add([pscustomobject]@{ Passed = $false; Check = 'SameVolume'; OperationId = $operation.OperationId; Detail = "Cross-volume move refused: $source -> $destination" })
        }
        $sourceExists = Test-Path -LiteralPath $source -PathType Leaf
        $destinationExists = Test-Path -LiteralPath $destination -PathType Leaf
        if ($sourceExists -and -not $destinationExists) {
            if ($UseCapturedHashEvidence) {
                $currentSize = [int64](Get-Item -LiteralPath $source).Length
                $expectedSize = [int64](Get-MigrationProperty $operation 'ExpectedSizeBytes' 0)
                $manifestHash = "$(Get-MigrationProperty $operation 'ManifestExpectedSha256' '')".ToLowerInvariant()
                $capturedHash = "$(Get-MigrationProperty $operation 'ExpectedSha256' '')".ToLowerInvariant()
                $evidence = if ($expectedSize -gt 0 -and $currentSize -ne $expectedSize) { [pscustomobject]@{ Passed = $false; Reason = "Size is $currentSize, expected $expectedSize" } }
                    elseif ($manifestHash -and $manifestHash -ne $capturedHash) { [pscustomobject]@{ Passed = $false; Reason = 'Captured SHA-256 differs from the inventory hash' } }
                    elseif (-not $capturedHash) { [pscustomobject]@{ Passed = $false; Reason = 'Dry run did not capture SHA-256 evidence' } }
                    else { [pscustomobject]@{ Passed = $true; Reason = 'Size and freshly captured SHA-256 evidence match' } }
            }
            else { $evidence = Test-FileAgainstOperation -Path $source -Operation $operation -RequireHash }
            $checks.Add([pscustomobject]@{ Passed = $evidence.Passed; Check = 'SourceEvidence'; OperationId = $operation.OperationId; Detail = "$source - $($evidence.Reason)" })
        }
        elseif ($AllowResumeState -and -not $sourceExists -and $destinationExists) {
            $evidence = Test-FileAgainstOperation -Path $destination -Operation $operation
            $checks.Add([pscustomobject]@{ Passed = $evidence.Passed; Check = 'RecoverableCompletedMove'; OperationId = $operation.OperationId; Detail = "$destination - $($evidence.Reason)" })
        }
        elseif ($sourceExists -and $destinationExists) {
            $checks.Add([pscustomobject]@{ Passed = $false; Check = 'NoOverwrite'; OperationId = $operation.OperationId; Detail = "Both source and destination exist: $source -> $destination" })
        }
        else {
            $checks.Add([pscustomobject]@{ Passed = $false; Check = 'FileState'; OperationId = $operation.OperationId; Detail = "Expected source is missing and no valid resumable destination exists: $source" })
        }
    }
    Write-Progress -Activity 'Migration preflight' -Completed
    return @($checks)
}

function Write-TransitionReport {
    param([object[]]$Rows, [string]$Directory)
    $csv = Join-Path $Directory 'plex-library-transition-mapping.csv'
    $markdown = Join-Path $Directory 'plex-library-transition-mapping.md'
    Write-MigrationCsv -Rows $Rows -Path $csv -Header '"InventoryId","Status","SourcePath","DestinationVideoPath","Classification","ExistingPlexLibrary","ExpectedPlexLibrary","TransitionType","PlexRatingKey","TmdbMovieId"'
    $within = @($Rows | Where-Object TransitionType -eq 'WithinExistingLibrary').Count
    $cross = @($Rows | Where-Object TransitionType -eq 'CrossLibraryBoundary').Count
    $unknown = @($Rows | Where-Object TransitionType -eq 'UnknownLibraryBoundary').Count
    $excluded = @($Rows | Where-Object TransitionType -eq 'ExcludedItemRemainsAtOriginalPath').Count
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# Plex library transition mapping')
    $lines.Add('')
    $lines.Add('This is a manual-review report. No Plex setting, path, scan or metadata was changed.')
    $lines.Add('')
    $lines.Add("- Ready moves within their existing Plex library: $within")
    $lines.Add("- Ready moves crossing an existing Plex library boundary: $cross")
    $lines.Add("- Ready moves with an unknown library boundary: $unknown")
    $lines.Add("- Review/Blocked files remaining at their original paths: $excluded")
    $lines.Add('')
    $lines.Add('Phase A keeps all three existing Plex libraries and their original configured locations. Add only the corresponding new location to each library: Movies -> `D:\Media Centre\Movies\1080p`; Movies 4K -> `D:\Media Centre\Movies\2160p`; Movies 3D -> `D:\Media Centre\Movies\3D`. Do not remove an original location while excluded files remain there.')
    $lines.Add('')
    $lines.Add('Any CrossLibraryBoundary or UnknownLibraryBoundary row blocks automated execution and needs a separately approved handling plan because Plex identity preservation across libraries is not assumed.')
    $lines.Add('')
    $lines.Add('| Status | Source library | Expected library | Transition | Source | Destination |')
    $lines.Add('| --- | --- | --- | --- | --- | --- |')
    foreach ($row in $Rows) {
        $lines.Add("| $($row.Status) | $(Escape-MigrationMarkdown $row.ExistingPlexLibrary) | $(Escape-MigrationMarkdown $row.ExpectedPlexLibrary) | $($row.TransitionType) | $(Escape-MigrationMarkdown $row.SourcePath) | $(Escape-MigrationMarkdown $row.DestinationVideoPath) |")
    }
    $lines | Set-Content -LiteralPath $markdown -Encoding UTF8
    return [pscustomobject]@{ Csv = $csv; Markdown = $markdown; CrossLibraryCount = $cross; UnknownLibraryCount = $unknown; ExcludedCount = $excluded }
}

if ($mode -eq 'DryRun') {
    $output = if ($OutputDirectory) { $OutputDirectory } else { Join-Path (Split-Path -Parent $context.Path) ("migration-readiness-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) }
    if ((Test-Path -LiteralPath $output -PathType Container) -and @(Get-ChildItem -LiteralPath $output -Force).Count -gt 0) { throw "Dry-run output directory is not empty: $output" }
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $operations = @(New-MigrationOperations -ReadyItems $context.ReadyItems -CaptureSidecarMetadata)
    $transitionRows = @(New-TransitionRows -Items $context.Items)
    $transition = Write-TransitionReport -Rows $transitionRows -Directory $output
    $checks = [Collections.Generic.List[object]]::new()
    if (@($operations).Count -eq 0) { $checks.Add([pscustomobject]@{ Passed = $false; Check = 'OperationScope'; OperationId = ''; Detail = 'Manifest contains no Ready file operations' }) }
    foreach ($check in @(Test-OperationSet -Operations $operations -AllowResumeState $false -TargetMoviesRoot $context.TargetMoviesRoot -UseCapturedHashEvidence $true)) { $checks.Add($check) }
    if ($transition.CrossLibraryCount -gt 0) { $checks.Add([pscustomobject]@{ Passed = $false; Check = 'PlexLibraryBoundary'; OperationId = ''; Detail = "$($transition.CrossLibraryCount) Ready movies cross existing Plex library boundaries" }) }
    if ($transition.UnknownLibraryCount -gt 0) { $checks.Add([pscustomobject]@{ Passed = $false; Check = 'PlexLibraryBoundary'; OperationId = ''; Detail = "$($transition.UnknownLibraryCount) Ready movies have unknown Plex library boundaries" }) }
    if ($transition.ExcludedCount -ne @($context.ExcludedItems).Count) { $checks.Add([pscustomobject]@{ Passed = $false; Check = 'ExcludedItems'; OperationId = ''; Detail = 'Transition report does not account for every excluded item' }) }
    $excludedEvidenceRows = [Collections.Generic.List[object]]::new()
    foreach ($excludedItem in $context.ExcludedItems) {
        $excludedSource = "$(Get-MigrationProperty $excludedItem 'SourcePath' '')"
        $excludedSize = [int64](Get-MigrationProperty $excludedItem 'SizeBytes' 0)
        $excludedHash = "$(Get-MigrationProperty $excludedItem 'Sha256' '')".ToLowerInvariant()
        if (-not $excludedHash -and (Test-Path -LiteralPath $excludedSource -PathType Leaf)) { $excludedHash = Get-FileSha256Lower $excludedSource }
        $excludedApprovalEvidence = [pscustomobject]@{ ExpectedSizeBytes = $excludedSize; ExpectedSha256 = $excludedHash }
        $excludedEvidence = Test-FileAgainstOperation -Path $excludedSource -Operation $excludedApprovalEvidence -RequireHash
        $checks.Add([pscustomobject]@{ Passed = $excludedEvidence.Passed; Check = 'ExcludedSourceEvidence'; OperationId = ''; Detail = "$excludedSource - $($excludedEvidence.Reason)" })
        $excludedEvidenceRows.Add([pscustomobject]@{ InventoryId = Get-MigrationProperty $excludedItem 'InventoryId'; Status = Get-MigrationProperty $excludedItem 'Status'; SourcePath = $excludedSource; ExpectedSizeBytes = $excludedSize; ExpectedSha256 = $excludedHash; ReviewReasons = (@(Get-MigrationProperty $excludedItem 'ReviewReasons' @()) -join '; '); BlockedReasons = (@(Get-MigrationProperty $excludedItem 'BlockedReasons' @()) -join '; ') })
    }
    $probePath = Join-Path $output '.journal-write-test'
    try { 'test' | Set-Content -LiteralPath $probePath -Encoding ASCII; Remove-Item -LiteralPath $probePath -Force; $checks.Add([pscustomobject]@{ Passed = $true; Check = 'JournalWritable'; OperationId = ''; Detail = $output }) }
    catch { $checks.Add([pscustomobject]@{ Passed = $false; Check = 'JournalWritable'; OperationId = ''; Detail = $_.Exception.Message }) }
    $passed = @($checks | Where-Object { -not $_.Passed }).Count -eq 0
    $preflightCsv = Join-Path $output 'migration-preflight.csv'
    Write-MigrationCsv -Rows @($checks) -Path $preflightCsv -Header '"Passed","Check","OperationId","Detail"'
    $dryRunCsv = Join-Path $output 'migration-dry-run.csv'
    Write-MigrationCsv -Rows $operations -Path $dryRunCsv -Header '"Sequence","OperationId","InventoryId","Kind","SourcePath","DestinationPath","ExpectedSizeBytes","ExpectedSha256"'
    $excludedCsv = Join-Path $output 'migration-excluded-items.csv'
    Write-MigrationCsv -Rows @($excludedEvidenceRows) -Path $excludedCsv -Header '"InventoryId","Status","SourcePath","ExpectedSizeBytes","ExpectedSha256","ReviewReasons","BlockedReasons"'
    $approval = [ordered]@{
        SchemaVersion = 1; GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o'); ApprovedForExecution = $passed
        ManifestPath = $context.Path; ManifestSha256 = $context.Sha256; ManifestItemCount = @($context.Items).Count; TargetMoviesRoot = $context.TargetMoviesRoot
        ReadyItemCount = @($context.ReadyItems).Count; ExcludedItemCount = @($context.ExcludedItems).Count; ExcludedIdsDigest = Get-MigrationItemIdDigest $context.ExcludedItems
        ExcludedEvidenceDigest = Get-MigrationExcludedEvidenceDigest @($excludedEvidenceRows); ExcludedEvidence = @($excludedEvidenceRows)
        OperationCount = @($operations).Count; OperationsDigest = Get-MigrationOperationsDigest $operations
        TransitionReportPath = $transition.Csv; TransitionReportSha256 = Get-FileSha256Lower $transition.Csv
        CrossLibraryReadyCount = $transition.CrossLibraryCount; UnknownLibraryReadyCount = $transition.UnknownLibraryCount
        Operations = $operations
    }
    $approvalFile = Join-Path $output 'migration-approval.json'
    $approval | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $approvalFile -Encoding UTF8
    $report = @(
        '# Movie migration dry run', '', '**No media files were changed.**', '',
        "- Readiness: $(if ($passed) { 'PASS' } else { 'FAIL' })", "- Manifest: $($context.Path)", "- Manifest SHA-256: $($context.Sha256)",
        "- Eligible Ready movies: $(@($context.ReadyItems).Count)", "- Excluded Review/Blocked movies: $(@($context.ExcludedItems).Count)",
        "- File operations (videos plus sidecars): $(@($operations).Count)", "- Cross-library Ready moves: $($transition.CrossLibraryCount)",
        "- Unknown-library Ready moves: $($transition.UnknownLibraryCount)", '', 'Execution remains blocked until Plex is stopped, the fresh stopped-state Plex backup is manually verified, and media writers are stopped. Those facts cannot be established by this report.', '',
        'Review `migration-preflight.csv`, `migration-dry-run.csv`, `migration-excluded-items.csv`, `plex-library-transition-mapping.csv`, and `migration-approval.json` before execution.'
    )
    $reportPath = Join-Path $output 'migration-dry-run.md'
    $report | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Host "Dry run $(if ($passed) { 'PASSED' } else { 'FAILED' }): $output"
    [pscustomobject]@{ Mode = 'DryRun'; Passed = $passed; OutputDirectory = $output; ApprovalPath = $approvalFile; DryRunReport = $reportPath; PreflightCsv = $preflightCsv; TransitionCsv = $transition.Csv; TransitionMarkdown = $transition.Markdown }
    return
}

if (-not $ApprovalPath -or -not (Test-Path -LiteralPath $ApprovalPath -PathType Leaf)) { throw '-ApprovalPath from a completed dry run is mandatory for execution or resume.' }
if (-not $PlexBackupVerified -or -not $PlexStoppedAcknowledged -or -not $MediaWritersStoppedAcknowledged) { throw 'Execution requires -PlexBackupVerified, -PlexStoppedAcknowledged and -MediaWritersStoppedAcknowledged.' }
if (-not $FixtureMode -and (Test-PlexRunning)) { throw 'Plex appears to be running. Stop Plex completely before execution.' }
$approvalResolved = (Resolve-Path -LiteralPath $ApprovalPath).Path
$approval = Get-Content -LiteralPath $approvalResolved -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not [bool](Get-MigrationProperty $approval 'ApprovedForExecution' $false)) { throw 'The dry-run approval is not marked ready for execution.' }
if ("$(Get-MigrationProperty $approval 'ManifestSha256' '')" -ne $context.Sha256) { throw 'The migration manifest changed after the approved dry run.' }
if ([int](Get-MigrationProperty $approval 'ReadyItemCount' -1) -ne @($context.ReadyItems).Count -or [int](Get-MigrationProperty $approval 'ExcludedItemCount' -1) -ne @($context.ExcludedItems).Count) { throw 'Ready or excluded manifest scope changed after the approved dry run.' }
if ("$(Get-MigrationProperty $approval 'ExcludedIdsDigest' '')" -ne (Get-MigrationItemIdDigest $context.ExcludedItems)) { throw 'The excluded Review/Blocked item set changed after the approved dry run.' }
$excludedEvidence = @(Get-MigrationProperty $approval 'ExcludedEvidence' @())
if (@($excludedEvidence).Count -ne @($context.ExcludedItems).Count -or "$(Get-MigrationProperty $approval 'ExcludedEvidenceDigest' '')" -ne (Get-MigrationExcludedEvidenceDigest $excludedEvidence)) { throw 'Approved excluded-file evidence is incomplete or has been altered.' }
foreach ($excluded in $excludedEvidence) {
    $evidence = Test-FileAgainstOperation -Path $excluded.SourcePath -Operation $excluded -RequireHash
    if (-not $evidence.Passed) { throw "Excluded source changed after dry run: $($excluded.SourcePath) - $($evidence.Reason)" }
}
$operations = @(Get-MigrationProperty $approval 'Operations' @())
if ([int](Get-MigrationProperty $approval 'OperationCount' -1) -ne @($operations).Count -or "$(Get-MigrationProperty $approval 'OperationsDigest' '')" -ne (Get-MigrationOperationsDigest $operations)) { throw 'Approved operation data is incomplete or has been altered.' }
$currentOperationIds = @(New-MigrationOperations -ReadyItems $context.ReadyItems | ForEach-Object OperationId | Sort-Object)
$approvedOperationIds = @($operations | ForEach-Object OperationId | Sort-Object)
if (($currentOperationIds -join "`n") -ne ($approvedOperationIds -join "`n")) { throw 'Approved operations no longer match the Ready items in the manifest.' }
$transitionPath = "$(Get-MigrationProperty $approval 'TransitionReportPath' '')"
if (-not (Test-Path -LiteralPath $transitionPath -PathType Leaf) -or (Get-FileSha256Lower $transitionPath) -ne "$(Get-MigrationProperty $approval 'TransitionReportSha256' '')") { throw 'The required Plex transition mapping is missing or changed.' }
if ([int](Get-MigrationProperty $approval 'CrossLibraryReadyCount' 0) -gt 0 -or [int](Get-MigrationProperty $approval 'UnknownLibraryReadyCount' 0) -gt 0) { throw 'Cross-library or unknown-library Ready moves require separate handling.' }

$journal = if ($JournalPath) { $JournalPath } else { Join-Path (Split-Path -Parent $approvalResolved) 'migration-execution-journal.ndjson' }
if ($mode -eq 'Resume' -and -not (Test-Path -LiteralPath $journal -PathType Leaf)) { throw "Resume requires the existing execution journal: $journal" }
$existingRecords = @(Read-MigrationJournal $journal)
$operationRecords = @($existingRecords | Where-Object { "$(Get-MigrationProperty $_ 'Event' '')" -in @('Started', 'Completed', 'RecoveredCompleted', 'Failed') })
if ($mode -eq 'Execute' -and @($operationRecords).Count -gt 0) { throw "Journal already contains operation records. Use -Resume with the same journal: $journal" }
foreach ($record in $existingRecords) {
    $recordManifest = "$(Get-MigrationProperty $record 'ManifestSha256' '')"
    if ($recordManifest -and $recordManifest -ne $context.Sha256) { throw 'Journal contains records for a different manifest.' }
}
$checks = @(Test-OperationSet -Operations $operations -AllowResumeState ($mode -eq 'Resume') -TargetMoviesRoot $context.TargetMoviesRoot -UseCapturedHashEvidence $false)
$failedChecks = @($checks | Where-Object { -not $_.Passed })
if (@($failedChecks).Count -gt 0) { throw "Execution preflight failed: $((@($failedChecks | ForEach-Object Detail) -join '; '))" }
$journalParent = Split-Path -Parent $journal
if (-not $journalParent) { $journalParent = (Get-Location).Path }
New-Item -ItemType Directory -Path $journalParent -Force | Out-Null
$journalProbe = Join-Path $journalParent ('.journal-probe-{0}' -f [guid]::NewGuid().ToString('N'))
try { 'probe' | Set-Content -LiteralPath $journalProbe -Encoding ASCII; Remove-Item -LiteralPath $journalProbe -Force }
catch { throw "Journal destination is not writable: $journalParent - $($_.Exception.Message)" }

$runId = [guid]::NewGuid().ToString('N')
$executionReport = Join-Path (Split-Path -Parent $approvalResolved) 'migration-execution-summary.md'
Add-MigrationJournalRecord -JournalPath $journal -Record @{ Event = 'RunStarted'; RunId = $runId; Mode = $mode; ManifestSha256 = $context.Sha256; ApprovalSha256 = (Get-FileSha256Lower $approvalResolved); OperationCount = @($operations).Count }
$completed = 0
try {
    foreach ($operation in @($operations | Sort-Object Sequence)) {
        $sourceExists = Test-Path -LiteralPath $operation.SourcePath -PathType Leaf
        $destinationExists = Test-Path -LiteralPath $operation.DestinationPath -PathType Leaf
        if (-not $sourceExists -and $destinationExists) {
            $verification = Test-FileAgainstOperation -Path $operation.DestinationPath -Operation $operation
            if (-not $verification.Passed) { throw "Resumable destination verification failed for $($operation.DestinationPath): $($verification.Reason)" }
            Add-MigrationJournalRecord -JournalPath $journal -Record @{ Event = 'RecoveredCompleted'; RunId = $runId; ManifestSha256 = $context.Sha256; OperationId = $operation.OperationId; InventoryId = $operation.InventoryId; Kind = $operation.Kind; SourcePath = $operation.SourcePath; DestinationPath = $operation.DestinationPath; ExpectedSizeBytes = $operation.ExpectedSizeBytes; ExpectedSha256 = $operation.ExpectedSha256 }
            $completed++
            continue
        }
        if (-not $sourceExists -or $destinationExists) { throw "Unsafe file state for $($operation.OperationId): source=$sourceExists destination=$destinationExists" }
        $sourceVerification = Test-FileAgainstOperation -Path $operation.SourcePath -Operation $operation
        if (-not $sourceVerification.Passed) { throw "Source changed after dry run: $($operation.SourcePath) - $($sourceVerification.Reason)" }
        Add-MigrationJournalRecord -JournalPath $journal -Record @{ Event = 'Started'; RunId = $runId; ManifestSha256 = $context.Sha256; OperationId = $operation.OperationId; InventoryId = $operation.InventoryId; Kind = $operation.Kind; SourcePath = $operation.SourcePath; DestinationPath = $operation.DestinationPath; ExpectedSizeBytes = $operation.ExpectedSizeBytes; ExpectedSha256 = $operation.ExpectedSha256 }
        $destinationParent = Split-Path -Parent $operation.DestinationPath
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        [IO.File]::Move($operation.SourcePath, $operation.DestinationPath)
        $destinationVerification = Test-FileAgainstOperation -Path $operation.DestinationPath -Operation $operation
        if (-not $destinationVerification.Passed) { throw "Post-move verification failed: $($operation.DestinationPath) - $($destinationVerification.Reason)" }
        Add-MigrationJournalRecord -JournalPath $journal -Record @{ Event = 'Completed'; RunId = $runId; ManifestSha256 = $context.Sha256; OperationId = $operation.OperationId; InventoryId = $operation.InventoryId; Kind = $operation.Kind; SourcePath = $operation.SourcePath; DestinationPath = $operation.DestinationPath; ExpectedSizeBytes = $operation.ExpectedSizeBytes; ExpectedSha256 = $operation.ExpectedSha256 }
        $completed++
        Write-Progress -Activity 'Moving approved media' -Status "$completed / $(@($operations).Count): $($operation.DestinationPath)" -PercentComplete (($completed / [math]::Max(1, @($operations).Count)) * 100)
    }
    Write-Progress -Activity 'Moving approved media' -Completed
    Add-MigrationJournalRecord -JournalPath $journal -Record @{ Event = 'RunCompleted'; RunId = $runId; Mode = $mode; ManifestSha256 = $context.Sha256; CompletedOperationCount = $completed }
}
catch {
    Add-MigrationJournalRecord -JournalPath $journal -Record @{ Event = 'RunFailed'; RunId = $runId; Mode = $mode; ManifestSha256 = $context.Sha256; CompletedOperationCount = $completed; Error = $_.Exception.Message }
    @('# Migration execution summary', '', '- Result: FAILED', "- Run ID: $runId", "- Mode: $mode", "- Completed or recovered operations before failure: $completed / $(@($operations).Count)", "- Journal: $journal", "- Error: $($_.Exception.Message)", '', 'Keep Plex and all media writers stopped. Inspect the journal and filesystem state, then use -Resume or perform a rollback dry run.') | Set-Content -LiteralPath $executionReport -Encoding UTF8
    throw
}

@('# Migration execution summary', '', '- Result: PASS', "- Run ID: $runId", "- Mode: $mode", "- Manifest SHA-256: $($context.Sha256)", "- Completed operations: $completed / $(@($operations).Count)", "- Journal: $journal", '', 'No original directories were cleaned up. Plex and media-management configuration were not changed.') | Set-Content -LiteralPath $executionReport -Encoding UTF8
Write-Host "Migration operations completed and verified: $completed. Run the separate verification command before touching Plex."
[pscustomobject]@{ Mode = $mode; RunId = $runId; JournalPath = $journal; CompletedOperationCount = $completed; ExecutionReport = $executionReport }

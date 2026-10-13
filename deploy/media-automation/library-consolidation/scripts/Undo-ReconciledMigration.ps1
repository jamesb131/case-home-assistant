[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$ApprovalPath,
    [Parameter(Mandatory = $true)][string]$JournalPath,
    [switch]$DryRun,
    [switch]$Execute,
    [string]$RollbackJournalPath,
    [string]$OutputDirectory,
    [switch]$PlexStoppedAcknowledged,
    [switch]$MediaWritersStoppedAcknowledged,
    [switch]$FixtureMode
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'MigrationExecutor.Common.ps1')

if ($DryRun -and $Execute) { throw 'Choose either -DryRun or -Execute.' }
$mode = if ($Execute) { 'Execute' } else { 'DryRun' }
$context = Read-MigrationManifest $ManifestPath
if ($FixtureMode) {
    $tempKey = Get-NormalizedMigrationPath ([IO.Path]::GetTempPath())
    if (-not (Get-NormalizedMigrationPath $context.Path).StartsWith($tempKey, [StringComparison]::OrdinalIgnoreCase)) { throw '-FixtureMode is restricted to manifests beneath the operating-system temp directory.' }
}
if (-not (Test-Path -LiteralPath $ApprovalPath -PathType Leaf)) { throw "Approval file not found: $ApprovalPath" }
$approvalResolved = (Resolve-Path -LiteralPath $ApprovalPath).Path
$approval = Get-Content -LiteralPath $approvalResolved -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not [bool](Get-MigrationProperty $approval 'ApprovedForExecution' $false)) { throw 'Approval is not marked ready for execution.' }
if ("$(Get-MigrationProperty $approval 'ManifestSha256' '')" -ne $context.Sha256) { throw 'Approval does not match the current manifest.' }
if ("$(Get-MigrationProperty $approval 'ExcludedIdsDigest' '')" -ne (Get-MigrationItemIdDigest $context.ExcludedItems)) { throw 'Approval excluded-item scope does not match the manifest.' }
$excludedEvidence = @(Get-MigrationProperty $approval 'ExcludedEvidence' @())
if (@($excludedEvidence).Count -ne @($context.ExcludedItems).Count -or "$(Get-MigrationProperty $approval 'ExcludedEvidenceDigest' '')" -ne (Get-MigrationExcludedEvidenceDigest $excludedEvidence)) { throw 'Approved excluded-file evidence is incomplete or has been altered.' }
$approvedOperations = @(Get-MigrationProperty $approval 'Operations' @())
if ([int](Get-MigrationProperty $approval 'OperationCount' -1) -ne @($approvedOperations).Count -or "$(Get-MigrationProperty $approval 'OperationsDigest' '')" -ne (Get-MigrationOperationsDigest $approvedOperations)) { throw 'Approved operation data is incomplete or has been altered.' }
$operationsById = @{}
foreach ($operation in $approvedOperations) { $operationsById["$($operation.OperationId)"] = $operation }
$journalRecords = @(Read-MigrationJournal $JournalPath)
foreach ($record in $journalRecords) {
    $recordManifest = "$(Get-MigrationProperty $record 'ManifestSha256' '')"
    if ($recordManifest -and $recordManifest -ne $context.Sha256) { throw 'Execution journal contains records for a different manifest.' }
}
$completedIds = @($journalRecords | Where-Object { "$(Get-MigrationProperty $_ 'Event' '')" -in @('Started', 'Completed', 'RecoveredCompleted') } | ForEach-Object { "$(Get-MigrationProperty $_ 'OperationId' '')" } | Where-Object { $_ } | Sort-Object -Unique)
$rollbackOperations = @($completedIds | ForEach-Object {
    if (-not $operationsById.ContainsKey($_)) { throw "Execution journal contains an operation outside the approved operation set: $_" }
    $original = $operationsById[$_]
    [pscustomobject]@{
        Sequence = [int]$original.Sequence; OperationId = $original.OperationId; InventoryId = $original.InventoryId; Kind = $original.Kind
        SourcePath = $original.DestinationPath; DestinationPath = $original.SourcePath
        ExpectedSizeBytes = [int64]$original.ExpectedSizeBytes; ExpectedSha256 = $original.ExpectedSha256
    }
} | Sort-Object Sequence -Descending)

$checks = [Collections.Generic.List[object]]::new()
if (@($rollbackOperations).Count -eq 0) { $checks.Add([pscustomobject]@{ Passed = $false; OperationId = ''; State = 'NoOperations'; Detail = 'Execution journal contains no started or completed operations to roll back' }) }
foreach ($excluded in $excludedEvidence) {
    $evidence = Test-FileAgainstOperation -Path $excluded.SourcePath -Operation $excluded -RequireHash
    $checks.Add([pscustomobject]@{ Passed = $evidence.Passed; OperationId = ''; State = 'ExcludedSourceEvidence'; Detail = "$($excluded.SourcePath) - $($evidence.Reason)" })
}
foreach ($operation in $rollbackOperations) {
    $migratedExists = Test-Path -LiteralPath $operation.SourcePath -PathType Leaf
    $originalExists = Test-Path -LiteralPath $operation.DestinationPath -PathType Leaf
    if ($migratedExists -and -not $originalExists) {
        $evidence = Test-FileAgainstOperation -Path $operation.SourcePath -Operation $operation
        $checks.Add([pscustomobject]@{ Passed = $evidence.Passed; OperationId = $operation.OperationId; State = 'ReadyToRollback'; Detail = $evidence.Reason })
    }
    elseif (-not $migratedExists -and $originalExists) {
        $evidence = Test-FileAgainstOperation -Path $operation.DestinationPath -Operation $operation
        $checks.Add([pscustomobject]@{ Passed = $evidence.Passed; OperationId = $operation.OperationId; State = 'AlreadyRolledBack'; Detail = $evidence.Reason })
    }
    elseif ($migratedExists -and $originalExists) { $checks.Add([pscustomobject]@{ Passed = $false; OperationId = $operation.OperationId; State = 'Collision'; Detail = 'Both migrated and original paths exist; overwrite refused' }) }
    else { $checks.Add([pscustomobject]@{ Passed = $false; OperationId = $operation.OperationId; State = 'Missing'; Detail = 'Neither migrated nor original path exists' }) }
}
$passed = @($checks | Where-Object { -not $_.Passed }).Count -eq 0
$output = if ($OutputDirectory) { $OutputDirectory } else { Split-Path -Parent $approvalResolved }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$preflightCsv = Join-Path $output 'rollback-preflight.csv'
Write-MigrationCsv -Rows @($checks) -Path $preflightCsv -Header '"Passed","OperationId","State","Detail"'
$report = Join-Path $output 'rollback-report.md'
@('# Migration rollback report', '', "- Mode: $mode", "- Preflight: $(if ($passed) { 'PASS' } else { 'FAIL' })", "- Journal-confirmed operations in scope: $(@($rollbackOperations).Count)", '', 'Rollback restores only journal-confirmed approved files. It does not remove destination directories or change Plex.') | Set-Content -LiteralPath $report -Encoding UTF8
if ($mode -eq 'DryRun') {
    Write-Host "Rollback dry run $(if ($passed) { 'PASSED' } else { 'FAILED' }): $report"
    [pscustomobject]@{ Mode = 'DryRun'; Passed = $passed; Report = $report; PreflightCsv = $preflightCsv; OperationCount = @($rollbackOperations).Count }
    return
}
if (@($rollbackOperations).Count -eq 0) { throw 'Execution journal contains no started or completed operations to roll back.' }
if (-not $passed) { throw 'Rollback preflight failed.' }
if (-not $PlexStoppedAcknowledged -or -not $MediaWritersStoppedAcknowledged) { throw 'Rollback execution requires -PlexStoppedAcknowledged and -MediaWritersStoppedAcknowledged.' }
if (-not $FixtureMode -and (Test-PlexRunning)) { throw 'Plex appears to be running. Stop Plex completely before rollback.' }
$rollbackJournal = if ($RollbackJournalPath) { $RollbackJournalPath } else { Join-Path $output 'migration-rollback-journal.ndjson' }
$runId = [guid]::NewGuid().ToString('N')
Add-MigrationJournalRecord -JournalPath $rollbackJournal -Record @{ Event = 'RollbackRunStarted'; RunId = $runId; ManifestSha256 = $context.Sha256; OperationCount = @($rollbackOperations).Count }
$completed = 0
try {
    foreach ($operation in $rollbackOperations) {
        $migratedExists = Test-Path -LiteralPath $operation.SourcePath -PathType Leaf
        $originalExists = Test-Path -LiteralPath $operation.DestinationPath -PathType Leaf
        if (-not $migratedExists -and $originalExists) {
            Add-MigrationJournalRecord -JournalPath $rollbackJournal -Record @{ Event = 'RollbackRecoveredCompleted'; RunId = $runId; ManifestSha256 = $context.Sha256; OperationId = $operation.OperationId; SourcePath = $operation.SourcePath; DestinationPath = $operation.DestinationPath }
            $completed++
            continue
        }
        Add-MigrationJournalRecord -JournalPath $rollbackJournal -Record @{ Event = 'RollbackStarted'; RunId = $runId; ManifestSha256 = $context.Sha256; OperationId = $operation.OperationId; SourcePath = $operation.SourcePath; DestinationPath = $operation.DestinationPath }
        New-Item -ItemType Directory -Path (Split-Path -Parent $operation.DestinationPath) -Force | Out-Null
        [IO.File]::Move($operation.SourcePath, $operation.DestinationPath)
        $verification = Test-FileAgainstOperation -Path $operation.DestinationPath -Operation $operation
        if (-not $verification.Passed) { throw "Rollback verification failed for $($operation.DestinationPath): $($verification.Reason)" }
        Add-MigrationJournalRecord -JournalPath $rollbackJournal -Record @{ Event = 'RollbackCompleted'; RunId = $runId; ManifestSha256 = $context.Sha256; OperationId = $operation.OperationId; SourcePath = $operation.SourcePath; DestinationPath = $operation.DestinationPath }
        $completed++
    }
    Add-MigrationJournalRecord -JournalPath $rollbackJournal -Record @{ Event = 'RollbackRunCompleted'; RunId = $runId; ManifestSha256 = $context.Sha256; CompletedOperationCount = $completed }
}
catch {
    Add-MigrationJournalRecord -JournalPath $rollbackJournal -Record @{ Event = 'RollbackRunFailed'; RunId = $runId; ManifestSha256 = $context.Sha256; CompletedOperationCount = $completed; Error = $_.Exception.Message }
    @('# Migration rollback report', '', '- Mode: Execute', '- Result: FAILED', "- Run ID: $runId", "- Reversed or already-restored operations before failure: $completed / $(@($rollbackOperations).Count)", "- Rollback journal: $rollbackJournal", "- Error: $($_.Exception.Message)", '', 'Keep Plex and media writers stopped. Inspect the rollback journal and filesystem state before retrying.') | Set-Content -LiteralPath $report -Encoding UTF8
    throw
}
@('# Migration rollback report', '', '- Mode: Execute', '- Result: PASS', "- Run ID: $runId", "- Restored operations: $completed / $(@($rollbackOperations).Count)", "- Rollback journal: $rollbackJournal", '', 'Original media paths were restored and verified. Empty target directories were intentionally left in place. Plex was not changed.') | Set-Content -LiteralPath $report -Encoding UTF8
Write-Host "Rollback completed and verified for $completed operations. Plex remains unchanged."
[pscustomobject]@{ Mode = 'Execute'; RunId = $runId; CompletedOperationCount = $completed; RollbackJournalPath = $rollbackJournal; Report = $report }

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$ApprovalPath,
    [Parameter(Mandatory = $true)][string]$JournalPath,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'MigrationExecutor.Common.ps1')

$context = Read-MigrationManifest $ManifestPath
if (-not (Test-Path -LiteralPath $ApprovalPath -PathType Leaf)) { throw "Approval file not found: $ApprovalPath" }
$approvalResolved = (Resolve-Path -LiteralPath $ApprovalPath).Path
$approval = Get-Content -LiteralPath $approvalResolved -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not [bool](Get-MigrationProperty $approval 'ApprovedForExecution' $false)) { throw 'Approval is not marked ready for execution.' }
if ("$(Get-MigrationProperty $approval 'ManifestSha256' '')" -ne $context.Sha256) { throw 'Approval does not match the current manifest.' }
if ("$(Get-MigrationProperty $approval 'ExcludedIdsDigest' '')" -ne (Get-MigrationItemIdDigest $context.ExcludedItems)) { throw 'Approval excluded-item scope does not match the manifest.' }
$excludedEvidence = @(Get-MigrationProperty $approval 'ExcludedEvidence' @())
if (@($excludedEvidence).Count -ne @($context.ExcludedItems).Count -or "$(Get-MigrationProperty $approval 'ExcludedEvidenceDigest' '')" -ne (Get-MigrationExcludedEvidenceDigest $excludedEvidence)) { throw 'Approved excluded-file evidence is incomplete or has been altered.' }
$operations = @(Get-MigrationProperty $approval 'Operations' @())
if ([int](Get-MigrationProperty $approval 'OperationCount' -1) -ne @($operations).Count -or "$(Get-MigrationProperty $approval 'OperationsDigest' '')" -ne (Get-MigrationOperationsDigest $operations)) { throw 'Approved operation data is incomplete or has been altered.' }
$journal = @(Read-MigrationJournal $JournalPath)
$completedIds = @($journal | Where-Object { "$(Get-MigrationProperty $_ 'Event' '')" -in @('Completed', 'RecoveredCompleted') } | ForEach-Object { "$(Get-MigrationProperty $_ 'OperationId' '')" } | Sort-Object -Unique)
$rows = [Collections.Generic.List[object]]::new()
foreach ($operation in $operations) {
    $destinationExists = Test-Path -LiteralPath $operation.DestinationPath -PathType Leaf
    $sourceExists = Test-Path -LiteralPath $operation.SourcePath -PathType Leaf
    $evidence = if ($destinationExists) { Test-FileAgainstOperation -Path $operation.DestinationPath -Operation $operation } else { [pscustomobject]@{ Passed = $false; Reason = 'Destination is missing' } }
    $journalCompleted = @($completedIds) -contains "$($operation.OperationId)"
    $passed = [bool]($destinationExists -and -not $sourceExists -and $evidence.Passed -and $journalCompleted)
    $rows.Add([pscustomobject]@{
        Passed = $passed; OperationId = $operation.OperationId; InventoryId = $operation.InventoryId; Kind = $operation.Kind
        SourcePath = $operation.SourcePath; DestinationPath = $operation.DestinationPath; SourceStillExists = $sourceExists
        DestinationExists = $destinationExists; JournalCompleted = $journalCompleted; Evidence = $evidence.Reason
    })
}
$excludedRows = [Collections.Generic.List[object]]::new()
foreach ($item in $excludedEvidence) {
    $source = "$($item.SourcePath)"
    $exists = Test-Path -LiteralPath $source -PathType Leaf
    $evidence = Test-FileAgainstOperation -Path $source -Operation $item -RequireHash
    $excludedRows.Add([pscustomobject]@{ Passed = $evidence.Passed; InventoryId = $item.InventoryId; Status = $item.Status; SourcePath = $source; SourceStillExists = $exists; Evidence = $evidence.Reason })
}
$passed = @($rows | Where-Object { -not $_.Passed }).Count -eq 0 -and @($excludedRows | Where-Object { -not $_.Passed }).Count -eq 0
$output = if ($OutputDirectory) { $OutputDirectory } else { Split-Path -Parent $approvalResolved }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$operationsCsv = Join-Path $output 'post-migration-verification.csv'
$excludedCsv = Join-Path $output 'post-migration-excluded-verification.csv'
Write-MigrationCsv -Rows @($rows) -Path $operationsCsv -Header '"Passed","OperationId","InventoryId","Kind","SourcePath","DestinationPath","SourceStillExists","DestinationExists","JournalCompleted","Evidence"'
Write-MigrationCsv -Rows @($excludedRows) -Path $excludedCsv -Header '"Passed","InventoryId","Status","SourcePath","SourceStillExists","Evidence"'
$report = Join-Path $output 'post-migration-verification.md'
@(
    '# Post-migration verification', '', "- Result: $(if ($passed) { 'PASS' } else { 'FAIL' })",
    "- Approved operations verified: $(@($rows | Where-Object Passed).Count) / $(@($rows).Count)",
    "- Excluded source files still present: $(@($excludedRows | Where-Object Passed).Count) / $(@($excludedRows).Count)",
    "- Manifest SHA-256: $($context.Sha256)", '',
    'A PASS verifies filesystem state, approved size/hash evidence and journal completion. It does not verify Plex metadata, watched status, posters, collections or version grouping.'
) | Set-Content -LiteralPath $report -Encoding UTF8
Write-Host "Post-migration verification $(if ($passed) { 'PASSED' } else { 'FAILED' }): $report"
[pscustomobject]@{ Passed = $passed; Report = $report; OperationsCsv = $operationsCsv; ExcludedCsv = $excludedCsv; OperationCount = @($rows).Count }
if (-not $passed) { throw 'Post-migration verification failed. Do not scan Plex or remove original library locations.' }

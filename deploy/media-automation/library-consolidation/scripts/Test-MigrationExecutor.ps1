[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'MigrationExecutor.Common.ps1')

function Assert-MigrationTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    Write-Host "PASS  $Message"
}

function New-TestManifestItem {
    param([string]$Id, [string]$Status, [string]$Source, [string]$Destination, [string]$Classification = '1080p', [string]$PlexLibrary = 'Movies', [object[]]$Sidecars = @())
    $file = Get-Item -LiteralPath $Source
    return [pscustomobject]@{
        InventoryId = $Id; Status = $Status; SourcePath = $file.FullName; DestinationVideoPath = $Destination
        Classification = $Classification; PlexLibrary = $PlexLibrary; PlexRatingKey = "rating-$Id"; TmdbMovieId = 100
        SizeBytes = [int64]$file.Length; Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        SubtitlePlans = $Sidecars; ReviewReasons = if ($Status -eq 'Review') { @('Fixture review') } else { @() }
        BlockedReasons = if ($Status -eq 'Blocked') { @('Fixture blocked') } else { @() }
    }
}

function Write-TestManifest {
    param([object[]]$Items, [string]$Path, [string]$TargetMoviesRoot)
    $ready = @($Items | Where-Object Status -eq 'Ready').Count
    $review = @($Items | Where-Object Status -eq 'Review').Count
    $blocked = @($Items | Where-Object Status -eq 'Blocked').Count
    [ordered]@{ SchemaVersion = 2; PlanningOnly = $true; TargetMoviesRoot = $TargetMoviesRoot; ItemCount = @($Items).Count; ReadyCount = $ready; ReviewCount = $review; BlockedCount = $blocked; Items = $Items } |
        ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$invokeScript = Join-Path $PSScriptRoot 'Invoke-ReconciledMigration.ps1'
$verifyScript = Join-Path $PSScriptRoot 'Test-ReconciledMigrationResult.ps1'
$rollbackScript = Join-Path $PSScriptRoot 'Undo-ReconciledMigration.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ("case-migration-executor-{0}" -f [guid]::NewGuid().ToString('N'))
try {
    $sourceRoot = Join-Path $root 'source'
    $targetRoot = Join-Path $root 'target'
    $reportRoot = Join-Path $root 'reports'
    New-Item -ItemType Directory -Path $sourceRoot, $targetRoot, $reportRoot -Force | Out-Null
    $video = Join-Path $sourceRoot 'Fixture Movie.mkv'
    $subtitle = Join-Path $sourceRoot 'Fixture Movie.en.srt'
    $excluded = Join-Path $sourceRoot 'Excluded Movie.mkv'
    [IO.File]::WriteAllText($video, 'fixture-video-original')
    [IO.File]::WriteAllText($subtitle, 'fixture-subtitle-original')
    [IO.File]::WriteAllText($excluded, 'fixture-excluded-original')
    $destinationFolder = Join-Path $targetRoot '1080p/Fixture Movie (2000)'
    $videoDestination = Join-Path $destinationFolder 'Fixture Movie (2000).mkv'
    $subtitleDestination = Join-Path $destinationFolder 'Fixture Movie (2000).en.srt'
    $sidecar = [pscustomobject]@{ SourcePath = $subtitle; DestinationPath = $subtitleDestination; Language = 'en'; Forced = $false; SDH = $false; SourceExists = $true }
    $items = @(
        (New-TestManifestItem -Id 'ready-1' -Status 'Ready' -Source $video -Destination $videoDestination -Sidecars @($sidecar)),
        (New-TestManifestItem -Id 'excluded-1' -Status 'Review' -Source $excluded -Destination (Join-Path $targetRoot '1080p/Excluded Movie (2001)/Excluded Movie (2001).mkv'))
    )
    $manifest = Join-Path $root 'migration-manifest.json'
    Write-TestManifest -Items $items -Path $manifest -TargetMoviesRoot $targetRoot

    $dryRun = & $invokeScript -ManifestPath $manifest -OutputDirectory $reportRoot
    Assert-MigrationTest $dryRun.Passed 'default invocation performs a passing dry run'
    Assert-MigrationTest ((Test-Path -LiteralPath $video) -and (Test-Path -LiteralPath $subtitle) -and -not (Test-Path -LiteralPath $videoDestination)) 'dry run does not move video or sidecar files'
    Assert-MigrationTest (@(Import-Csv -LiteralPath (Join-Path $reportRoot 'migration-excluded-items.csv')).Count -eq 1) 'dry run proves the excluded item is outside execution scope'

    $originalVideoBytes = [IO.File]::ReadAllBytes($video)
    $changedVideoBytes = [byte[]]$originalVideoBytes.Clone()
    $changedVideoBytes[0] = if ($changedVideoBytes[0] -eq 88) { 89 } else { 88 }
    [IO.File]::WriteAllBytes($video, $changedVideoBytes)
    $sourceChangeBlocked = $false
    try { & $invokeScript -ManifestPath $manifest -Execute -ApprovalPath $dryRun.ApprovalPath -PlexBackupVerified -PlexStoppedAcknowledged -MediaWritersStoppedAcknowledged -FixtureMode | Out-Null }
    catch { $sourceChangeBlocked = $_.Exception.Message -match 'preflight failed|Source changed' }
    Assert-MigrationTest $sourceChangeBlocked 'execution refuses a source changed after dry run'
    [IO.File]::WriteAllBytes($video, $originalVideoBytes)

    $alteredManifest = Join-Path $root 'altered-manifest.json'
    Copy-Item -LiteralPath $manifest -Destination $alteredManifest
    [IO.File]::AppendAllText($alteredManifest, ' ')
    $manifestChangeBlocked = $false
    try { & $invokeScript -ManifestPath $alteredManifest -Execute -ApprovalPath $dryRun.ApprovalPath -PlexBackupVerified -PlexStoppedAcknowledged -MediaWritersStoppedAcknowledged -FixtureMode | Out-Null }
    catch { $manifestChangeBlocked = $_.Exception.Message -match 'manifest changed' }
    Assert-MigrationTest $manifestChangeBlocked 'execution refuses a manifest changed after approval'

    # Simulate interruption after the sidecar filesystem move but before its completion record.
    $approval = Get-Content -LiteralPath $dryRun.ApprovalPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $sidecarOperation = @($approval.Operations | Where-Object Kind -eq 'Sidecar')[0]
    New-Item -ItemType Directory -Path (Split-Path -Parent $sidecarOperation.DestinationPath) -Force | Out-Null
    [IO.File]::Move($sidecarOperation.SourcePath, $sidecarOperation.DestinationPath)
    $journal = Join-Path $reportRoot 'migration-execution-journal.ndjson'
    Add-MigrationJournalRecord -JournalPath $journal -Record @{ Event = 'Started'; RunId = 'fixture-interrupted'; ManifestSha256 = (Get-FileSha256Lower $manifest); OperationId = $sidecarOperation.OperationId; InventoryId = $sidecarOperation.InventoryId; Kind = 'Sidecar'; SourcePath = $sidecarOperation.SourcePath; DestinationPath = $sidecarOperation.DestinationPath }
    $resume = & $invokeScript -ManifestPath $manifest -Resume -ApprovalPath $dryRun.ApprovalPath -JournalPath $journal -PlexBackupVerified -PlexStoppedAcknowledged -MediaWritersStoppedAcknowledged -FixtureMode
    Assert-MigrationTest ($resume.CompletedOperationCount -eq 2) 'resume recovers the interrupted sidecar and completes the video move'
    Assert-MigrationTest ((Test-Path -LiteralPath $videoDestination) -and (Test-Path -LiteralPath $subtitleDestination) -and (Test-Path -LiteralPath $excluded)) 'resume moves approved files and leaves excluded media untouched'

    $verification = & $verifyScript -ManifestPath $manifest -ApprovalPath $dryRun.ApprovalPath -JournalPath $journal -OutputDirectory $reportRoot
    Assert-MigrationTest $verification.Passed 'post-migration verification validates journal, destinations and excluded files'

    $rollbackDryRun = & $rollbackScript -ManifestPath $manifest -ApprovalPath $dryRun.ApprovalPath -JournalPath $journal -OutputDirectory $reportRoot
    Assert-MigrationTest $rollbackDryRun.Passed 'rollback dry run validates every journal-confirmed operation'
    $rollback = & $rollbackScript -ManifestPath $manifest -ApprovalPath $dryRun.ApprovalPath -JournalPath $journal -Execute -OutputDirectory $reportRoot -PlexStoppedAcknowledged -MediaWritersStoppedAcknowledged -FixtureMode
    Assert-MigrationTest ($rollback.CompletedOperationCount -eq 2) 'rollback reverses all completed approved operations'
    Assert-MigrationTest ((Test-Path -LiteralPath $video) -and (Test-Path -LiteralPath $subtitle) -and -not (Test-Path -LiteralPath $videoDestination) -and (Test-Path -LiteralPath $excluded)) 'rollback restores approved sources without touching excluded media'

    $collisionOne = Join-Path $sourceRoot 'Collision One.mkv'
    $collisionTwo = Join-Path $sourceRoot 'Collision Two.mkv'
    [IO.File]::WriteAllText($collisionOne, 'collision-one')
    [IO.File]::WriteAllText($collisionTwo, 'collision-two')
    $collisionDestination = Join-Path $targetRoot '1080p/Collision (2002)/Collision (2002).mkv'
    $collisionManifest = Join-Path $root 'collision-manifest.json'
    Write-TestManifest -Items @(
        (New-TestManifestItem -Id 'collision-1' -Status 'Ready' -Source $collisionOne -Destination $collisionDestination),
        (New-TestManifestItem -Id 'collision-2' -Status 'Ready' -Source $collisionTwo -Destination $collisionDestination)
    ) -Path $collisionManifest -TargetMoviesRoot $targetRoot
    $collisionRun = & $invokeScript -ManifestPath $collisionManifest -OutputDirectory (Join-Path $root 'collision-report')
    Assert-MigrationTest (-not $collisionRun.Passed) 'dry run refuses a case-insensitive destination collision'
    Assert-MigrationTest ((Test-Path -LiteralPath $collisionOne) -and (Test-Path -LiteralPath $collisionTwo)) 'collision test leaves both sources unchanged'

    $crossLibrarySource = Join-Path $sourceRoot 'Cross Library.mkv'
    [IO.File]::WriteAllText($crossLibrarySource, 'cross-library')
    $crossLibraryManifest = Join-Path $root 'cross-library-manifest.json'
    Write-TestManifest -Items @(
        (New-TestManifestItem -Id 'cross-library' -Status 'Ready' -Source $crossLibrarySource -Destination (Join-Path $targetRoot '2160p/Cross Library (2003)/Cross Library (2003).mkv') -Classification '2160p' -PlexLibrary 'Movies')
    ) -Path $crossLibraryManifest -TargetMoviesRoot $targetRoot
    $crossLibraryRun = & $invokeScript -ManifestPath $crossLibraryManifest -OutputDirectory (Join-Path $root 'cross-library-report')
    Assert-MigrationTest (-not $crossLibraryRun.Passed) 'Ready move crossing an existing Plex library boundary fails readiness'
    Assert-MigrationTest (@(Import-Csv -LiteralPath $crossLibraryRun.TransitionCsv | Where-Object TransitionType -eq 'CrossLibraryBoundary').Count -eq 1) 'transition mapping identifies the cross-library movie explicitly'
    Write-Host 'Migration executor fixture checks passed.'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

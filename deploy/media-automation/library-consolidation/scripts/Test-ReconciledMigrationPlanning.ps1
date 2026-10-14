[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    Write-Host "PASS  $Message"
}

function New-PlanFixtureItem {
    param(
        [string]$Id, [string]$Path, [AllowNull()][object]$TmdbId, [string]$Title, [AllowNull()][object]$Year,
        [string]$CollectionHint, [string]$Resolution, [string]$PlexLibrary, [string]$RatingKey,
        [string[]]$Issues = @(), [string]$Edition = '', [object[]]$Subtitles = @(), [string[]]$InventoryReasons = @(),
        [string]$ProbeStatus = 'Completed'
    )
    $file = Get-Item -LiteralPath $Path
    return [pscustomobject]@{
        InventoryId = $Id; OriginalPath = $file.FullName; OriginalTitle = $file.BaseName; OriginalYear = $null; Collection = "$CollectionHint source"
        CollectionHint = $CollectionHint; ResolutionClass = $Resolution; ThreeDFormat = if ($CollectionHint -eq '3D') { 'Unknown 3D' } else { $null }
        OriginalEdition = $Edition; IdentificationSource = if ($null -eq $TmdbId) { 'Unresolved' } else { 'PlexTMDB' }; ReconciledTmdbMovieId = $TmdbId
        CanonicalTitle = $Title; CanonicalReleaseYear = $Year; PlexRatingKey = $RatingKey; PlexLibrary = $PlexLibrary; PlexOriginalFilePath = $file.FullName
        ReviewIssues = $Issues
        OriginalEnrichedItem = [pscustomobject]@{
            OriginalInventoryItem = [pscustomobject]@{
                Extension = $file.Extension; SizeBytes = [int64]$file.Length; Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
                Width = if ($Resolution -eq '2160p') { 3840 } else { 1920 }; Height = if ($Resolution -eq '2160p') { 2160 } else { 1080 }
                HdrFormat = $null; ExternalSubtitles = $Subtitles; ReviewReasons = $InventoryReasons; ProbeStatus = $ProbeStatus
            }
        }
    }
}

$scriptPath = Join-Path $PSScriptRoot 'New-ReconciledMigrationPlan.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("case-reconciled-plan-{0}" -f [guid]::NewGuid().ToString('N'))
try {
    $sourceRoot = Join-Path $fixtureRoot 'sources'
    $targetRoot = Join-Path $fixtureRoot 'target/Movies'
    $outputRoot = Join-Path $fixtureRoot 'reports'
    New-Item -ItemType Directory -Path $sourceRoot, $targetRoot -Force | Out-Null

    function New-FixtureFile {
        param([string]$RelativePath, [string]$Content = 'fixture-media')
        $path = Join-Path $sourceRoot $RelativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        Set-Content -LiteralPath $path -Value $Content -Encoding UTF8
        return (Get-Item -LiteralPath $path).FullName
    }

    $toy3dPath = New-FixtureFile '3D/Toy Story 3D.mkv'
    $toy3Path = New-FixtureFile '1080p/Toy Story 3.mkv'
    $matrix1080Path = New-FixtureFile '1080p/The Matrix.mkv'
    $matrix2160Path = New-FixtureFile '2160p/The Matrix 4K.mkv'
    $subtitlePath = New-FixtureFile '1080p/The Matrix.en.forced.srt' 'subtitle'
    $blackadderPath = New-FixtureFile "1080p/Blackadder$([char]0x2019)s Christmas Carol.mkv"
    $collisionOnePath = New-FixtureFile '1080p-a/Collision.mkv' 'collision-one'
    $collisionTwoPath = New-FixtureFile '1080p-b/Collision.mkv' 'collision-two'
    $unresolvedPath = New-FixtureFile '1080p/Unknown.mkv'
    $wrongQualityPath = New-FixtureFile '1080p/Actually 4K.mkv'
    $directorPath = New-FixtureFile '1080p/Film Director.mkv'
    $theatricalPath = New-FixtureFile '1080p/Film Theatrical.mkv'
    $conflictPath = New-FixtureFile '1080p/Conflicted.mkv'
    $ordinaryPath = New-FixtureFile '1080p/Ordinary Root Movie.mkv'
    $probeWarningPath = New-FixtureFile '1080p/Probe Warning Movie.mkv'

    $matrixSubtitle = [pscustomobject]@{ Path = $subtitlePath; Extension = '.srt'; Language = 'en'; Forced = $true; SDH = $false }
    $items = @(
        (New-PlanFixtureItem 'toy-3d' $toy3dPath 10193 'Toy Story 3' 2010 '3D' '1080p' 'Movies 3D' '1' @('PlexTmdbConflict') '3D'),
        (New-PlanFixtureItem 'toy-3' $toy3Path 10193 'Toy Story 3' 2010 '1080p' '1080p' 'Movies' '2'),
        (New-PlanFixtureItem 'matrix-1080' $matrix1080Path 603 'The Matrix' 1999 '1080p' '1080p' 'Movies' '3' @() '' @($matrixSubtitle)),
        (New-PlanFixtureItem 'matrix-2160' $matrix2160Path 603 'The Matrix' 1999 '2160p' '2160p' 'Movies 4K' '4'),
        (New-PlanFixtureItem 'blackadder' $blackadderPath 214484 'Blackadder''s Christmas Carol' 1988 '1080p' '1080p' 'Movies' '5'),
        (New-PlanFixtureItem 'collision-1' $collisionOnePath 700 'Collision Film' 2000 '1080p' '1080p' 'Movies' '6'),
        (New-PlanFixtureItem 'collision-2' $collisionTwoPath 700 'Collision Film' 2000 '1080p' '1080p' 'Movies' '7'),
        (New-PlanFixtureItem 'unresolved' $unresolvedPath $null '' $null '1080p' '1080p' '' '' @('Unresolved')),
        (New-PlanFixtureItem 'wrong-quality' $wrongQualityPath 800 'Actually 4K' 2020 '1080p' '2160p' 'Movies' '8'),
        (New-PlanFixtureItem 'director' $directorPath 900 'Two Cuts' 2001 '1080p' '1080p' 'Movies' '9' @() 'Director''s Cut'),
        (New-PlanFixtureItem 'theatrical' $theatricalPath 900 'Two Cuts' 2001 '1080p' '1080p' 'Movies' '10' @() 'Theatrical Cut'),
        (New-PlanFixtureItem 'conflict' $conflictPath 1000 'Conflicted' 2002 '1080p' '1080p' 'Movies' '11' @('PlexTmdbConflict')),
        (New-PlanFixtureItem 'ordinary-root' $ordinaryPath 1100 'Ordinary Root Movie' 2003 '1080p' '1080p' 'Movies' '12' @() '' @() @('Video is stored directly in the collection root', 'Multiple video files share this folder', 'Release year could not be inferred', 'Quality based on source collection hint', 'Resolution does not match the 2160p collection hint')),
        (New-PlanFixtureItem 'probe-warning' $probeWarningPath 1200 'Probe Warning Movie' 2004 '1080p' '1080p' 'Movies' '13' @() '' @() @('ffprobe reported malformed media stream data: Invalid NAL unit size') 'CompletedWithStreamErrors')
    )
    ($items | Where-Object InventoryId -eq 'blackadder').PlexOriginalFilePath = ''

    $inventoryPath = Join-Path $fixtureRoot 'plex-reconciled-inventory.json'
    [ordered]@{ SchemaVersion = 1; ItemCount = @($items).Count; Items = $items } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $inventoryPath -Encoding UTF8
    $configPath = Join-Path $fixtureRoot 'reconciled-migration.config.json'
    [ordered]@{
        targetMoviesRoot = $targetRoot
        qualityFolders = [ordered]@{ '1080p' = '1080p'; '2160p' = '2160p'; '3D' = '3D' }
        threeDAssumption = 'Fixture user-reported SBS assumption; technically unverified.'
        outputDirectory = $outputRoot
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
    $overridePath = Join-Path $fixtureRoot 'migration-overrides.csv'
    @([pscustomobject]@{ SourcePath = $toy3dPath; TmdbMovieId = 862; CanonicalTitle = 'Toy Story'; CanonicalReleaseYear = 1995; Reason = 'Explicit 3D source-path correction' }) |
        Export-Csv -LiteralPath $overridePath -NoTypeInformation -Encoding UTF8
    $exclusionPath = Join-Path $fixtureRoot 'migration-exclusions.csv'
    @([pscustomobject]@{ SourcePath = $blackadderPath; Reason = 'User-approved fixture exclusion; leave source untouched' }) |
        Export-Csv -LiteralPath $exclusionPath -NoTypeInformation -Encoding UTF8
    $plexReviewPath = Join-Path $fixtureRoot 'plex-reconciliation-review.csv'
    @([pscustomobject]@{ InventoryId = ''; PlexOriginalFilePath = (Join-Path (Split-Path -Parent $blackadderPath) "Blackadder's Christmas Carol.mkv"); Issues = 'PlexPartNotInInventory' }) |
        Export-Csv -LiteralPath $plexReviewPath -NoTypeInformation -Encoding UTF8

    $sourceHashes = @{}
    Get-ChildItem -LiteralPath $sourceRoot -File -Recurse | ForEach-Object { $sourceHashes[$_.FullName] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    $result = & $scriptPath -ReconciledInventoryPath $inventoryPath -ConfigPath $configPath -OverridesPath $overridePath -ExclusionsPath $exclusionPath -PlexReviewPath $plexReviewPath

    foreach ($path in @($result.ManifestJson, $result.ManifestCsv, $result.SummaryMarkdown, $result.ExceptionCsv, $result.ExceptionMarkdown, $result.CrossVersionGroupsCsv, $result.PathAnalysisCsv, $result.CollisionCsv, $result.CollisionMarkdown, $result.MediaHealthCsv, $result.MediaHealthMarkdown, $result.PreflightJson, $result.PreflightMarkdown, $result.RollbackJson, $result.RollbackCsv, $result.PlexTransitionMarkdown)) {
        Assert-True -Condition (Test-Path -LiteralPath $path -PathType Leaf) -Message "required planning output exists: $([IO.Path]::GetFileName($path))"
    }
    $manifest = Get-Content -LiteralPath $result.ManifestJson -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Condition ($manifest.PlanningOnly -and $manifest.ItemCount -eq 14) -Message 'planner includes every reconciled video and remains planning-only'
    $toy3d = $manifest.Items | Where-Object InventoryId -eq 'toy-3d'
    $toy3 = $manifest.Items | Where-Object InventoryId -eq 'toy-3'
    Assert-True -Condition ($toy3d.OverrideApplied -and $toy3d.TmdbMovieId -eq 862 -and $toy3d.CanonicalTitle -eq 'Toy Story' -and $toy3d.CanonicalReleaseYear -eq 1995) -Message 'exact source-path override corrects only the 3D Toy Story file'
    Assert-True -Condition ($toy3d.Status -eq 'Ready' -and $toy3d.InformationalWarnings -match 'PlexTmdbConflict') -Message 'validated override clears its identity conflict while retaining the disagreement in the audit trail'
    Assert-True -Condition ($toy3.TmdbMovieId -eq 10193 -and -not $toy3.OverrideApplied) -Message 'standard Toy Story 3 identification is unchanged'
    Assert-True -Condition ($toy3d.Classification -eq '3D' -and $toy3d.Assumptions -contains 'Fixture user-reported SBS assumption; technically unverified.') -Message '3D SBS is recorded as an assumption rather than verified metadata'
    Assert-True -Condition ($toy3d.DestinationVideoPath -notmatch '\{edition-3D') -Message 'unverified 3D layout marker is not promoted to a Plex edition label'
    $matrix1080 = $manifest.Items | Where-Object InventoryId -eq 'matrix-1080'
    $matrix2160 = $manifest.Items | Where-Object InventoryId -eq 'matrix-2160'
    Assert-True -Condition ($matrix1080.CrossVersionGroupId -eq 'tmdb-603' -and $matrix2160.CrossVersionGroupId -eq 'tmdb-603') -Message '1080p and 2160p variants share a TMDB cross-version group'
    Assert-True -Condition ($matrix1080.SubtitlePlans.Count -eq 1 -and $matrix1080.SubtitlePlans[0].DestinationPath -match '\.en\.forced\.srt$') -Message 'associated subtitle language and forced status are preserved'
    Assert-True -Condition (@($manifest.Items | Where-Object { $_.InventoryId -like 'collision-*' -and $_.Status -eq 'Blocked' -and $_.DestinationCollision }).Count -eq 2) -Message 'case-insensitive destination collisions block every participant'
    Assert-True -Condition (($manifest.Items | Where-Object InventoryId -eq 'unresolved').Status -eq 'Blocked') -Message 'unresolved identity remains blocked'
    Assert-True -Condition (($manifest.Items | Where-Object InventoryId -eq 'wrong-quality').Status -eq 'Review') -Message 'possible 4K content in the standard collection is flagged for review'
    Assert-True -Condition (@($manifest.Items | Where-Object { $_.InventoryId -in @('director', 'theatrical') -and $_.MultipleCut -and $_.Status -eq 'Review' }).Count -eq 2) -Message 'multiple cuts remain separate and require review'
    Assert-True -Condition (($manifest.Items | Where-Object InventoryId -eq 'conflict').Status -eq 'Review') -Message 'Plex/TMDB conflict is not silently accepted as ready'
    $ordinary = $manifest.Items | Where-Object InventoryId -eq 'ordinary-root'
    Assert-True -Condition ($ordinary.Status -eq 'Ready' -and @($ordinary.HistoricalInventoryWarnings).Count -eq 5 -and @($ordinary.ReviewReasons).Count -eq 0) -Message 'root-level, shared-folder, stale-quality and missing-filename-year history is informational after current validation'
    $probeWarning = $manifest.Items | Where-Object InventoryId -eq 'probe-warning'
    Assert-True -Condition ($probeWarning.Status -eq 'Ready' -and @($probeWarning.MediaHealthWarnings).Count -eq 1) -Message 'ffprobe stream warning is reported without automatically holding migration'
    Assert-True -Condition (@(Import-Csv -LiteralPath $result.MediaHealthCsv | Where-Object InventoryId -eq 'probe-warning').Count -eq 1) -Message 'media-health report contains probe warning evidence'
    Assert-True -Condition (@(Import-Csv -LiteralPath $result.CollisionCsv).Count -eq 2) -Message 'collision evidence report retains both conflicting source files'
    Assert-True -Condition (($manifest.ReadyCount + $manifest.ReviewCount + $manifest.BlockedCount) -eq $manifest.ItemCount) -Message 'status counts reconcile with the full manifest'
    Assert-True -Condition (@(Import-Csv -LiteralPath $result.ExceptionCsv).Count -eq ($manifest.ReviewCount + $manifest.BlockedCount)) -Message 'exception CSV count equals Review plus Blocked'
    $pathRows = @(Import-Csv -LiteralPath $result.PathAnalysisCsv)
    $blackadder = $pathRows | Where-Object InventoryId -eq 'blackadder'
    Assert-True -Condition ($blackadder.CandidateUnmatchedPlexPaths -match "Blackadder's Christmas Carol") -Message 'Unicode punctuation and UTF-8 Plex path mismatch is surfaced'
    $blackadderPlan = $manifest.Items | Where-Object InventoryId -eq 'blackadder'
    Assert-True -Condition ($blackadderPlan.Status -eq 'Blocked' -and $blackadderPlan.ExplicitlyExcluded -and $blackadderPlan.ProposedAction -eq 'Hold') -Message 'exact-path exclusion keeps Blackadder outside the operation set'
    Assert-True -Condition ($blackadderPlan.ExclusionReason -eq 'User-approved fixture exclusion; leave source untouched' -and $blackadderPlan.BlockedReasons -match 'Explicit exact-path exclusion') -Message 'exclusion reason is retained in the manifest audit trail'
    Assert-True -Condition ($manifest.SourceExclusionsSha256 -eq (Get-FileHash -LiteralPath $exclusionPath -Algorithm SHA256).Hash) -Message 'manifest fingerprints the exact-path exclusion input'
    $rollback = Get-Content -LiteralPath $result.RollbackJson -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Condition ($rollback.PlanningOnly -and @($rollback.Items).Count -eq 14) -Message 'rollback manifest covers every planned source'
    foreach ($path in $sourceHashes.Keys) {
        Assert-True -Condition ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $sourceHashes[$path]) -Message "source remains unchanged: $([IO.Path]::GetFileName($path))"
    }

    $unmatchedExclusionPath = Join-Path $fixtureRoot 'migration-exclusions-unmatched.csv'
    @([pscustomobject]@{ SourcePath = (Join-Path $sourceRoot '1080p/Not Present.mkv'); Reason = 'Fixture unmatched path' }) |
        Export-Csv -LiteralPath $unmatchedExclusionPath -NoTypeInformation -Encoding UTF8
    $unmatchedFailed = $false
    try {
        & $scriptPath -ReconciledInventoryPath $inventoryPath -ConfigPath $configPath -OverridesPath $overridePath -ExclusionsPath $unmatchedExclusionPath -PlexReviewPath $plexReviewPath | Out-Null
    }
    catch {
        $unmatchedFailed = $_.Exception.Message -match 'Migration exclusion did not match any reconciled source path'
    }
    Assert-True -Condition $unmatchedFailed -Message 'an unmatched exclusion path terminates planning instead of silently changing scope'
    Write-Host 'Reconciled migration planning fixture checks passed.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}

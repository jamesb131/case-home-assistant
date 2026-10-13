[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReconciledInventoryPath,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [string]$OverridesPath,

    [string]$PlexReviewPath,

    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-ObjectProperty {
    param([AllowNull()][object]$Object, [string]$Name, [AllowNull()][object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function ConvertTo-PathKey {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $value = $Path.Trim().Trim('"').Replace('/', '\')
    if ($value.StartsWith('\\?\')) { $value = $value.Substring(4) }
    $isUnc = $value.StartsWith('\\')
    $value = [regex]::Replace($value, '\\+', '\')
    if ($isUnc) { $value = "\$value" }
    return $value.TrimEnd('\').Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
}

function Test-PathPrefix {
    param([string]$PathKey, [string]$PrefixKey)
    if (-not $PathKey -or -not $PrefixKey) { return $false }
    return [bool]($PathKey -eq $PrefixKey -or $PathKey.StartsWith("$PrefixKey\", [StringComparison]::OrdinalIgnoreCase))
}

function ConvertTo-SafeName {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $clean = [regex]::Replace($Value, '[<>:"/\\|?*]', ' ')
    return [regex]::Replace($clean, '\s+', ' ').Trim().TrimEnd([char[]]@('.', ' '))
}

function Get-LooseUnicodeKey {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $normalized = $Value.Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
    $apostrophePattern = "[$([char]0x2018)$([char]0x2019)$([char]0x02BC)]"
    $quotePattern = "[$([char]0x201C)$([char]0x201D)]"
    $normalized = [regex]::Replace($normalized, $apostrophePattern, "'")
    $normalized = [regex]::Replace($normalized, $quotePattern, '"')
    return [regex]::Replace($normalized, '\s+', ' ').Trim()
}

function Escape-Markdown {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return "$Value".Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function Write-CsvSafe {
    param([object[]]$Rows, [string]$Path, [string]$Header)
    if (@($Rows).Count -gt 0) { $Rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 }
    else { $Header | Set-Content -LiteralPath $Path -Encoding UTF8 }
}

function Test-MediaHealthWarning {
    param([AllowNull()][string]$Reason)
    return [bool]($Reason -match '(?i)ffprobe|malformed media|stream data|video dimensions are unavailable')
}

function Test-QualityMismatchWarning {
    param([AllowNull()][string]$Reason)
    return [bool]($Reason -match '(?i)resolution does not match|resolution appears 4k|wrong (?:source )?collection|quality mismatch')
}

function Test-IdentityConflictIssue {
    param([AllowNull()][string]$Issue)
    return [bool]($Issue -in @('PlexTmdbConflict', 'MultiplePlexTmdbIds', 'MultiplePlexImdbIds', 'DuplicatePlexFileMappings'))
}

if (-not (Test-Path -LiteralPath $ReconciledInventoryPath -PathType Leaf)) { throw "Reconciled inventory not found: $ReconciledInventoryPath" }
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Migration planning configuration not found: $ConfigPath" }
if ($OverridesPath -and -not (Test-Path -LiteralPath $OverridesPath -PathType Leaf)) { throw "Migration override file not found: $OverridesPath" }
if ($PlexReviewPath -and -not (Test-Path -LiteralPath $PlexReviewPath -PathType Leaf)) { throw "Plex review file not found: $PlexReviewPath" }

$resolvedInventoryPath = (Resolve-Path -LiteralPath $ReconciledInventoryPath).Path
$inventory = Get-Content -LiteralPath $resolvedInventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$config = Get-Content -LiteralPath (Resolve-Path -LiteralPath $ConfigPath).Path -Raw -Encoding UTF8 | ConvertFrom-Json
$items = @(Get-ObjectProperty $inventory 'Items' @())
$declaredItemCount = Get-ObjectProperty $inventory 'ItemCount' $null
if ($null -ne $declaredItemCount -and [int]$declaredItemCount -ne @($items).Count) { throw "Reconciled inventory declares $declaredItemCount items but $(@($items).Count) were parsed." }
$targetRoot = "$(Get-ObjectProperty $config 'targetMoviesRoot' '')".Trim()
$qualityFolders = Get-ObjectProperty $config 'qualityFolders'
$threeDAssumption = "$(Get-ObjectProperty $config 'threeDAssumption' 'User reports the existing 3D collection is probably SBS; this has not been technically verified.')".Trim()
if (-not $targetRoot -or $targetRoot -match '(?i)replace_with|change[_-]?me') { throw 'Configure targetMoviesRoot before planning.' }
foreach ($quality in @('1080p', '2160p', '3D')) {
    if ([string]::IsNullOrWhiteSpace("$(Get-ObjectProperty $qualityFolders $quality '')")) { throw "Configure qualityFolders.$quality before planning." }
}

$baseOutput = if ($OutputDirectory) { $OutputDirectory } else { "$(Get-ObjectProperty $config 'outputDirectory' '')".Trim() }
if (-not $baseOutput) { $baseOutput = Split-Path -Parent $resolvedInventoryPath }
$outputKey = ConvertTo-PathKey $baseOutput
$targetKey = ConvertTo-PathKey $targetRoot
if (Test-PathPrefix $outputKey $targetKey) { throw 'Planning output must remain outside the target movie collection.' }
foreach ($item in $items) {
    $sourceRoot = Get-ObjectProperty (Get-ObjectProperty (Get-ObjectProperty $item 'OriginalEnrichedItem') 'OriginalInventoryItem') 'RootPath'
    $sourceRootKey = ConvertTo-PathKey "$sourceRoot"
    if ($sourceRootKey -and (Test-PathPrefix $outputKey $sourceRootKey)) { throw "Planning output must remain outside source media root: $sourceRoot" }
}
New-Item -ItemType Directory -Path $baseOutput -Force | Out-Null
$runDirectory = Join-Path $baseOutput ("reconciled-migration-plan-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

$overridesByPath = @{}
if ($OverridesPath) {
    $overrideRows = @(Get-Content -LiteralPath $OverridesPath -Raw -Encoding UTF8 | ConvertFrom-Csv)
    foreach ($override in $overrideRows) {
        $sourcePath = "$($override.SourcePath)".Trim()
        $key = ConvertTo-PathKey $sourcePath
        if (-not $key) { throw 'Every migration override requires an exact SourcePath.' }
        if ($overridesByPath.ContainsKey($key)) { throw "Duplicate migration override for source path: $sourcePath" }
        if ("$($override.TmdbMovieId)" -notmatch '^\d+$' -or [int]$override.TmdbMovieId -le 0) { throw "Migration override requires a numeric TMDB ID: $sourcePath" }
        if (-not "$($override.CanonicalTitle)".Trim() -or "$($override.CanonicalReleaseYear)" -notmatch '^\d{4}$') { throw "Migration override requires canonical title and four-digit year: $sourcePath" }
        $overridesByPath[$key] = $override
    }
}

$unmatchedPlexParts = @()
if ($PlexReviewPath) {
    $plexReviewRows = @(Get-Content -LiteralPath $PlexReviewPath -Raw -Encoding UTF8 | ConvertFrom-Csv)
    $unmatchedPlexParts = @($plexReviewRows | Where-Object { @("$($_.Issues)" -split ';') -contains 'PlexPartNotInInventory' })
}

$planItems = @()
$seenOverridePaths = @{}
foreach ($item in $items) {
    $sourcePath = "$(Get-ObjectProperty $item 'OriginalPath' '')"
    $sourceKey = ConvertTo-PathKey $sourcePath
    $originalEnriched = Get-ObjectProperty $item 'OriginalEnrichedItem'
    $source = Get-ObjectProperty $originalEnriched 'OriginalInventoryItem'
    $informationalWarnings = @()
    $historicalInventoryWarnings = @()
    $mediaHealthWarnings = @()
    $reviewReasons = @()
    $blockedReasons = @()
    $assumptions = @()

    $tmdbId = Get-ObjectProperty $item 'ReconciledTmdbMovieId'
    $title = "$(Get-ObjectProperty $item 'CanonicalTitle' '')".Trim()
    $year = Get-ObjectProperty $item 'CanonicalReleaseYear'
    $identitySource = "$(Get-ObjectProperty $item 'IdentificationSource' '')"
    $overrideApplied = $false
    $overrideReason = $null
    if ($overridesByPath.ContainsKey($sourceKey)) {
        $override = $overridesByPath[$sourceKey]
        $tmdbId = [int]$override.TmdbMovieId
        $title = "$($override.CanonicalTitle)".Trim()
        $year = [int]$override.CanonicalReleaseYear
        $identitySource = 'ExplicitSourcePathOverride'
        $overrideReason = "$($override.Reason)".Trim()
        $overrideApplied = $true
        $seenOverridePaths[$sourceKey] = $true
    }

    if ($null -eq $tmdbId -or "$tmdbId" -notmatch '^\d+$' -or [int]$tmdbId -le 0) { $blockedReasons += 'No reconciled TMDB movie ID' }
    if (-not $title) { $blockedReasons += 'Canonical title is missing' }
    if ($null -eq $year -or "$year" -notmatch '^\d{4}$') { $blockedReasons += 'Canonical release year is missing or invalid' }

    $collectionHint = "$(Get-ObjectProperty $item 'CollectionHint' '')"
    $resolutionClass = "$(Get-ObjectProperty $item 'ResolutionClass' '')"
    $classification = $null
    if ($collectionHint -eq '3D') {
        $classification = '3D'
        $assumptions += $threeDAssumption
    }
    elseif ($resolutionClass -in @('1080p', '2160p')) { $classification = $resolutionClass }
    elseif ($collectionHint -in @('1080p', '2160p')) {
        $classification = $collectionHint
        $informationalWarnings += 'Quality classification relies on the source collection hint because measured resolution is unavailable'
    }
    else { $blockedReasons += 'Target quality could not be classified' }

    if ($collectionHint -eq '1080p' -and $classification -eq '2160p') { $reviewReasons += 'Possible 4K file currently stored in the standard movie collection' }
    if ($collectionHint -eq '2160p' -and $classification -eq '1080p') { $reviewReasons += 'Possible standard-resolution file currently stored in the 4K collection' }
    if ($collectionHint -eq '3D' -and $classification -ne '3D') { $reviewReasons += 'File from the 3D source collection was classified outside 3D' }

    foreach ($issue in @(Get-ObjectProperty $item 'ReviewIssues' @())) {
        if ($issue -eq 'Unverified3DLayout' -and $classification -eq '3D') {
            $informationalWarnings += 'Reconciliation audit: 3D layout remains technically unverified'
            continue
        }
        if ($issue -eq 'Unresolved') { $blockedReasons += 'Reconciled identity remains unresolved' }
        elseif ($issue -eq 'DuplicateInventoryPath') { $blockedReasons += 'Duplicate source path in reconciled inventory' }
        elseif (Test-IdentityConflictIssue $issue) {
            if ($overrideApplied) { $informationalWarnings += "Override audit: reconciliation issue '$issue' was resolved by the validated exact source-path override" }
            elseif ($issue -eq 'PlexTmdbConflict') { $reviewReasons += 'Plex and prior TMDB identifications conflict' }
            else { $reviewReasons += "Reconciliation identity conflict: $issue" }
        }
        else { $informationalWarnings += "Reconciliation audit: $issue" }
    }
    foreach ($reason in @(Get-ObjectProperty $source 'ReviewReasons' @())) {
        $historicalInventoryWarnings += "$reason"
        if (Test-MediaHealthWarning "$reason") { $mediaHealthWarnings += "$reason"; continue }
        if ("$reason" -match '(?i)sha-256 failed') { $reviewReasons += "Integrity evidence unavailable: $reason"; continue }
        if (Test-QualityMismatchWarning "$reason") {
            $informationalWarnings += "Inventory quality audit: $reason; migration status uses the current measured-resolution comparison"
            continue
        }
        if ($classification -eq '3D' -and "$reason" -match '(?i)3D layout') {
            $informationalWarnings += "Inventory audit: $reason"
            continue
        }
        if ("$reason" -match '(?i)release year could not be inferred' -and $tmdbId -and "$year" -match '^\d{4}$') {
            $informationalWarnings += "Inventory audit: $reason; canonical year $year is confirmed by reconciliation"
            continue
        }
        $informationalWarnings += "Inventory audit: $reason"
    }

    $safeTitle = ConvertTo-SafeName $title
    $folderName = if ($safeTitle -and "$year" -match '^\d{4}$') { "$safeTitle ($year)" } else { $null }
    $edition = ConvertTo-SafeName "$(Get-ObjectProperty $item 'OriginalEdition' '')"
    if ($classification -eq '3D' -and $edition -match '(?i)^3D(?:\s+(?:H?SBS|SBS|H?TAB|TAB|OU))?$') {
        $assumptions += "Source edition label '$edition' was treated as an unverified 3D/layout marker, not a confirmed Plex edition."
        $edition = ''
    }
    $videoStem = $folderName
    if ($videoStem -and $edition) { $videoStem = "$videoStem {edition-$edition}" }
    $extension = "$(Get-ObjectProperty $source 'Extension' ([IO.Path]::GetExtension($sourcePath)))"
    $qualityFolder = if ($classification) { "$(Get-ObjectProperty $qualityFolders $classification '')" } else { $null }
    $destinationFolder = if ($folderName -and $qualityFolder) { Join-Path (Join-Path $targetRoot $qualityFolder) $folderName } else { $null }
    $destinationVideo = if ($destinationFolder -and $videoStem) { Join-Path $destinationFolder "$videoStem$extension" } else { $null }

    $subtitlePlans = @()
    foreach ($subtitle in @(Get-ObjectProperty $source 'ExternalSubtitles' @())) {
        $subtitleSource = "$(Get-ObjectProperty $subtitle 'Path' '')"
        $language = "$(Get-ObjectProperty $subtitle 'Language' '')".Trim()
        $suffixParts = @()
        if ($language) { $suffixParts += $language } else { $reviewReasons += "Subtitle language requires review: $subtitleSource" }
        if ([bool](Get-ObjectProperty $subtitle 'Forced' $false)) { $suffixParts += 'forced' }
        elseif ([bool](Get-ObjectProperty $subtitle 'SDH' $false)) { $suffixParts += 'sdh' }
        $suffix = if (@($suffixParts).Count -gt 0) { '.' + ($suffixParts -join '.') } else { '' }
        $subtitleExtension = "$(Get-ObjectProperty $subtitle 'Extension' ([IO.Path]::GetExtension($subtitleSource)))"
        $subtitlePlans += [pscustomobject]@{
            SourcePath = $subtitleSource
            DestinationPath = if ($destinationFolder -and $videoStem) { Join-Path $destinationFolder "$videoStem$suffix$subtitleExtension" } else { $null }
            Language = $language
            Forced = [bool](Get-ObjectProperty $subtitle 'Forced' $false)
            SDH = [bool](Get-ObjectProperty $subtitle 'SDH' $false)
            SourceExists = [bool](Test-Path -LiteralPath $subtitleSource -PathType Leaf)
        }
    }

    $plexPath = "$(Get-ObjectProperty $item 'PlexOriginalFilePath' '')"
    $unicodeCandidates = @()
    if (-not $plexPath -and @($unmatchedPlexParts).Count -gt 0) {
        $sourceLeafKey = Get-LooseUnicodeKey ([IO.Path]::GetFileName($sourcePath))
        foreach ($part in $unmatchedPlexParts) {
            $candidatePath = "$($part.PlexOriginalFilePath)"
            if ($sourceLeafKey -and $sourceLeafKey -eq (Get-LooseUnicodeKey ([IO.Path]::GetFileName($candidatePath)))) { $unicodeCandidates += $candidatePath }
        }
        if (@($unicodeCandidates).Count -gt 0) { $reviewReasons += 'Unmatched Plex path has a Unicode-normalized filename candidate' }
    }
    $pathAnalysis = [pscustomobject]@{
        InventoryPath = $sourcePath
        PlexPath = $plexPath
        OrdinalIgnoreCaseEqual = [bool]($plexPath -and [string]::Equals($sourcePath, $plexPath, [StringComparison]::OrdinalIgnoreCase))
        FormCEqual = [bool]($plexPath -and [string]::Equals($sourcePath.Normalize([Text.NormalizationForm]::FormC), $plexPath.Normalize([Text.NormalizationForm]::FormC), [StringComparison]::OrdinalIgnoreCase))
        FormDEqual = [bool]($plexPath -and [string]::Equals($sourcePath.Normalize([Text.NormalizationForm]::FormD), $plexPath.Normalize([Text.NormalizationForm]::FormD), [StringComparison]::OrdinalIgnoreCase))
        ContainsReplacementCharacter = [bool]($sourcePath.Contains([char]0xFFFD) -or $plexPath.Contains([char]0xFFFD))
        CandidateUnmatchedPlexPaths = @($unicodeCandidates)
        CandidateMatchBasis = if (@($unicodeCandidates).Count -gt 0) { 'UnicodeNFCAndPunctuationNormalizedFileName' } else { $null }
        CsvReadEncoding = if ($PlexReviewPath) { 'UTF-8' } else { $null }
    }

    $sourceExists = [bool](Test-Path -LiteralPath $sourcePath -PathType Leaf)
    if (-not $sourceExists) { $blockedReasons += 'Source video does not exist at planning time' }
    $destinationExists = [bool]($destinationVideo -and (Test-Path -LiteralPath $destinationVideo -PathType Leaf))
    if ($destinationExists -and -not [string]::Equals($sourcePath, $destinationVideo, [StringComparison]::OrdinalIgnoreCase)) { $blockedReasons += 'Destination video already exists; overwrite is prohibited' }
    foreach ($subtitlePlan in $subtitlePlans) {
        if (-not $subtitlePlan.SourceExists) { $blockedReasons += "Associated subtitle is missing: $($subtitlePlan.SourcePath)" }
        if ($subtitlePlan.DestinationPath -and (Test-Path -LiteralPath $subtitlePlan.DestinationPath -PathType Leaf) -and -not [string]::Equals($subtitlePlan.SourcePath, $subtitlePlan.DestinationPath, [StringComparison]::OrdinalIgnoreCase)) {
            $blockedReasons += "Subtitle destination already exists: $($subtitlePlan.DestinationPath)"
        }
    }

    $planItems += [pscustomobject]@{
        InventoryId = Get-ObjectProperty $item 'InventoryId'
        SourcePath = $sourcePath
        SourceCollection = Get-ObjectProperty $item 'Collection'
        SourceCollectionHint = $collectionHint
        SourceExists = $sourceExists
        SizeBytes = [int64](Get-ObjectProperty $source 'SizeBytes' 0)
        Sha256 = Get-ObjectProperty $source 'Sha256'
        IdentificationSource = $identitySource
        OverrideApplied = $overrideApplied
        OverrideReason = $overrideReason
        TmdbMovieId = $tmdbId
        CanonicalTitle = $title
        CanonicalReleaseYear = $year
        PlexRatingKey = Get-ObjectProperty $item 'PlexRatingKey'
        PlexLibrary = Get-ObjectProperty $item 'PlexLibrary'
        PlexOriginalFilePath = $plexPath
        Classification = $classification
        ResolutionClass = $resolutionClass
        Width = Get-ObjectProperty $source 'Width'
        Height = Get-ObjectProperty $source 'Height'
        HdrFormat = Get-ObjectProperty $source 'HdrFormat'
        ProbeStatus = Get-ObjectProperty $source 'ProbeStatus'
        ProbeTimedOut = [bool](Get-ObjectProperty $source 'ProbeTimedOut' $false)
        ProbeStderrLineCount = Get-ObjectProperty $source 'ProbeStderrLineCount' 0
        ProbeStderrSummary = Get-ObjectProperty $source 'ProbeStderrSummary'
        ExistingEdition = $edition
        ThreeDFormat = Get-ObjectProperty $item 'ThreeDFormat'
        DestinationFolder = $destinationFolder
        DestinationVideoPath = $destinationVideo
        DestinationExists = $destinationExists
        SubtitlePlans = $subtitlePlans
        Assumptions = @($assumptions | Select-Object -Unique)
        HistoricalInventoryWarnings = @($historicalInventoryWarnings | Select-Object -Unique)
        InformationalWarnings = @($informationalWarnings | Select-Object -Unique)
        MediaHealthWarnings = @($mediaHealthWarnings | Select-Object -Unique)
        ReviewReasons = @($reviewReasons | Select-Object -Unique)
        BlockedReasons = @($blockedReasons | Select-Object -Unique)
        PathAnalysis = $pathAnalysis
        CrossVersionGroupId = if ($tmdbId) { "tmdb-$tmdbId" } else { $null }
        DestinationCollision = $false
        DuplicateVersion = $false
        MultipleCut = $false
        Status = $null
        ProposedAction = 'PlanMove'
    }
}

foreach ($overrideKey in $overridesByPath.Keys) {
    if (-not $seenOverridePaths.ContainsKey($overrideKey)) { throw "Migration override did not match any reconciled source path: $($overridesByPath[$overrideKey].SourcePath)" }
}

$collisionGroups = @($planItems | Where-Object DestinationVideoPath | Group-Object { (ConvertTo-PathKey $_.DestinationVideoPath) } | Where-Object Count -gt 1)
foreach ($group in $collisionGroups) {
    foreach ($planItem in $group.Group) {
        $planItem.DestinationCollision = $true
        $planItem.BlockedReasons = @(($planItem.BlockedReasons + 'Case-insensitive destination path collision') | Select-Object -Unique)
    }
}

$allDestinationRecords = @()
foreach ($planItem in $planItems) {
    if ($planItem.DestinationVideoPath) { $allDestinationRecords += [pscustomobject]@{ Owner = $planItem; Path = $planItem.DestinationVideoPath; Kind = 'Video' } }
    foreach ($subtitlePlan in @($planItem.SubtitlePlans)) {
        if ($subtitlePlan.DestinationPath) { $allDestinationRecords += [pscustomobject]@{ Owner = $planItem; Path = $subtitlePlan.DestinationPath; Kind = 'Subtitle' } }
    }
}
$destinationPathGroups = @($allDestinationRecords | Group-Object { ConvertTo-PathKey $_.Path } | Where-Object Count -gt 1)
foreach ($group in $destinationPathGroups) {
    foreach ($record in $group.Group) {
        $record.Owner.BlockedReasons = @(($record.Owner.BlockedReasons + "Case-insensitive destination collision involving $($record.Kind): $($record.Path)") | Select-Object -Unique)
    }
}

$versionGroups = @($planItems | Where-Object TmdbMovieId | Group-Object TmdbMovieId)
$crossVersionRows = @()
foreach ($group in $versionGroups) {
    $variants = @($group.Group.Classification | Sort-Object -Unique)
    $classGroups = @($group.Group | Group-Object Classification)
    foreach ($classGroup in $classGroups) {
        if ($classGroup.Count -gt 1) {
            $editions = @($classGroup.Group.ExistingEdition | Where-Object { $_ } | Sort-Object -Unique)
            foreach ($planItem in $classGroup.Group) {
                if (@($editions).Count -gt 1) {
                    $planItem.MultipleCut = $true
                    $planItem.ReviewReasons = @(($planItem.ReviewReasons + 'Multiple cuts or editions share this TMDB ID and quality') | Select-Object -Unique)
                }
                else {
                    $planItem.DuplicateVersion = $true
                    $planItem.ReviewReasons = @(($planItem.ReviewReasons + 'Multiple files share this TMDB ID and quality classification') | Select-Object -Unique)
                }
            }
        }
    }
    foreach ($planItem in $group.Group) {
        $crossVersionRows += [pscustomobject]@{
            GroupId = "tmdb-$($group.Name)"; TmdbMovieId = $group.Name; CanonicalTitle = $planItem.CanonicalTitle; InventoryId = $planItem.InventoryId
            Classification = $planItem.Classification; ExistingEdition = $planItem.ExistingEdition; SourcePath = $planItem.SourcePath; DestinationVideoPath = $planItem.DestinationVideoPath
            GroupVariants = ($variants -join ';'); DuplicateVersion = $planItem.DuplicateVersion; MultipleCut = $planItem.MultipleCut
        }
    }
}

foreach ($planItem in $planItems) {
    $planItem.Status = if (@($planItem.BlockedReasons).Count -gt 0) { 'Blocked' } elseif (@($planItem.ReviewReasons).Count -gt 0) { 'Review' } else { 'Ready' }
    if ($planItem.Status -ne 'Ready') { $planItem.ProposedAction = 'Hold' }
}

$readyCount = @($planItems | Where-Object Status -eq 'Ready').Count
$reviewCount = @($planItems | Where-Object Status -eq 'Review').Count
$blockedCount = @($planItems | Where-Object Status -eq 'Blocked').Count
$exceptionCount = $reviewCount + $blockedCount
if (($readyCount + $reviewCount + $blockedCount) -ne @($planItems).Count) { throw 'Status counts do not reconcile with the full migration manifest.' }
$collisionRows = @($collisionGroups | ForEach-Object {
    $collisionKey = $_.Name
    $_.Group | ForEach-Object {
        [pscustomobject]@{
            CollisionKey = $collisionKey; DestinationVideoPath = $_.DestinationVideoPath; InventoryId = $_.InventoryId; SourcePath = $_.SourcePath
            SourceCollection = $_.SourceCollection; Classification = $_.Classification; TmdbMovieId = $_.TmdbMovieId; CanonicalTitle = $_.CanonicalTitle
            CanonicalReleaseYear = $_.CanonicalReleaseYear; ExistingEdition = $_.ExistingEdition; Width = $_.Width; Height = $_.Height; SizeBytes = $_.SizeBytes
            Sha256 = $_.Sha256; PlexRatingKey = $_.PlexRatingKey; PlexLibrary = $_.PlexLibrary
            Disposition = 'Hold for evidence-based review; do not merge, overwrite, arbitrarily rename or re-identify'
        }
    }
})
$mediaHealthRows = @($planItems | Where-Object { @($_.MediaHealthWarnings).Count -gt 0 } | ForEach-Object {
    [pscustomobject]@{
        InventoryId = $_.InventoryId; SourcePath = $_.SourcePath; CanonicalTitle = $_.CanonicalTitle; Status = $_.Status
        ProbeStatus = $_.ProbeStatus; ProbeTimedOut = $_.ProbeTimedOut; ProbeStderrLineCount = $_.ProbeStderrLineCount; ProbeStderrSummary = $_.ProbeStderrSummary
        Warnings = ($_.MediaHealthWarnings -join '; ')
    }
})

$requiredBytes = [int64]0
foreach ($planItem in $planItems) { $requiredBytes += [int64]$planItem.SizeBytes }
$targetDriveFreeBytes = $null
if ($targetRoot -match '^(?<drive>[A-Za-z]):\\') {
    $drive = Get-PSDrive -Name $Matches['drive'] -ErrorAction SilentlyContinue
    if ($drive) { $targetDriveFreeBytes = [int64]$drive.Free }
}
$preflight = [ordered]@{
    PlanningOnly = $true
    SourceItemCount = @($planItems).Count
    SourceFilesPresent = @($planItems | Where-Object SourceExists).Count
    SourceFilesMissing = @($planItems | Where-Object { -not $_.SourceExists }).Count
    DestinationFilesAlreadyPresent = @($planItems | Where-Object DestinationExists).Count
    PlannedSourceBytes = $requiredBytes
    PlannedSourceGiB = [math]::Round($requiredBytes / 1GB, 3)
    TargetDriveFreeBytes = $targetDriveFreeBytes
    TargetDriveFreeGiB = if ($null -ne $targetDriveFreeBytes) { [math]::Round($targetDriveFreeBytes / 1GB, 3) } else { $null }
    StorageNote = 'A same-volume move normally needs negligible additional capacity. A future executor must recalculate space and detect cross-volume copies before any operation.'
}

$rollbackRows = @($planItems | ForEach-Object {
    [pscustomobject]@{
        InventoryId = $_.InventoryId; Status = $_.Status; OriginalSourcePath = $_.SourcePath; ProposedDestinationPath = $_.DestinationVideoPath
        RollbackSourcePath = $_.DestinationVideoPath; RollbackDestinationPath = $_.SourcePath; ExpectedSizeBytes = $_.SizeBytes; ExpectedSha256 = $_.Sha256
        Requirement = 'Future execution must verify destination size/hash and preserve this original path before rollback can be approved.'
    }
})

$generatedAt = (Get-Date).ToUniversalTime().ToString('o')
$manifest = [ordered]@{
    SchemaVersion = 2; GeneratedAtUtc = $generatedAt; Tool = 'New-ReconciledMigrationPlan.ps1'; PlanningOnly = $true
    SourceReconciledInventory = $resolvedInventoryPath; SourceSha256 = (Get-FileHash -LiteralPath $resolvedInventoryPath -Algorithm SHA256).Hash
    TargetMoviesRoot = $targetRoot; ItemCount = @($planItems).Count; ReadyCount = $readyCount
    ReviewCount = $reviewCount; BlockedCount = $blockedCount; ExceptionCount = $exceptionCount
    CollisionGroupCount = @($collisionGroups).Count; CrossVersionGroupCount = @($versionGroups | Where-Object Count -gt 1).Count
    Preflight = $preflight; Items = $planItems
}

$manifestJson = Join-Path $runDirectory 'migration-manifest.json'
$manifestCsv = Join-Path $runDirectory 'migration-manifest.csv'
$summaryPath = Join-Path $runDirectory 'planning-summary.md'
$exceptionCsv = Join-Path $runDirectory 'migration-exceptions.csv'
$exceptionMarkdown = Join-Path $runDirectory 'migration-exceptions.md'
$groupsCsv = Join-Path $runDirectory 'cross-version-groups.csv'
$collisionCsv = Join-Path $runDirectory 'destination-collisions.csv'
$collisionMarkdown = Join-Path $runDirectory 'destination-collisions.md'
$mediaHealthCsv = Join-Path $runDirectory 'media-health.csv'
$mediaHealthMarkdown = Join-Path $runDirectory 'media-health.md'
$pathAnalysisCsv = Join-Path $runDirectory 'plex-path-analysis.csv'
$preflightJson = Join-Path $runDirectory 'preflight.json'
$preflightMarkdown = Join-Path $runDirectory 'preflight.md'
$rollbackJson = Join-Path $runDirectory 'rollback-manifest.json'
$rollbackCsv = Join-Path $runDirectory 'rollback-manifest.csv'
$plexTransitionPath = Join-Path $runDirectory 'plex-transition-plan.md'

$manifest | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $manifestJson -Encoding UTF8
$manifestRows = @($planItems | ForEach-Object {
    [pscustomobject]@{
        InventoryId = $_.InventoryId; Status = $_.Status; SourcePath = $_.SourcePath; DestinationVideoPath = $_.DestinationVideoPath; Classification = $_.Classification
        TmdbMovieId = $_.TmdbMovieId; CanonicalTitle = $_.CanonicalTitle; CanonicalReleaseYear = $_.CanonicalReleaseYear; IdentificationSource = $_.IdentificationSource
        PlexRatingKey = $_.PlexRatingKey; PlexLibrary = $_.PlexLibrary; CrossVersionGroupId = $_.CrossVersionGroupId; ExistingEdition = $_.ExistingEdition
        SubtitleCount = @($_.SubtitlePlans).Count; OverrideApplied = $_.OverrideApplied; DestinationCollision = $_.DestinationCollision; DuplicateVersion = $_.DuplicateVersion
        MultipleCut = $_.MultipleCut; Assumptions = ($_.Assumptions -join '; '); HistoricalInventoryWarnings = ($_.HistoricalInventoryWarnings -join '; ')
        InformationalWarnings = ($_.InformationalWarnings -join '; '); MediaHealthWarnings = ($_.MediaHealthWarnings -join '; ')
        ReviewReasons = ($_.ReviewReasons -join '; '); BlockedReasons = ($_.BlockedReasons -join '; ')
    }
})
$manifestHeader = '"InventoryId","Status","SourcePath","DestinationVideoPath","Classification","TmdbMovieId","CanonicalTitle","CanonicalReleaseYear","IdentificationSource","PlexRatingKey","PlexLibrary","CrossVersionGroupId","ExistingEdition","SubtitleCount","OverrideApplied","DestinationCollision","DuplicateVersion","MultipleCut","Assumptions","HistoricalInventoryWarnings","InformationalWarnings","MediaHealthWarnings","ReviewReasons","BlockedReasons"'
Write-CsvSafe -Rows $manifestRows -Path $manifestCsv -Header $manifestHeader
$exceptionRows = @($manifestRows | Where-Object Status -ne 'Ready')
Write-CsvSafe -Rows $exceptionRows -Path $exceptionCsv -Header $manifestHeader
if (@($exceptionRows).Count -ne $exceptionCount) { throw 'Exception rows do not reconcile with Review plus Blocked counts.' }
$writtenExceptionCount = @(Import-Csv -LiteralPath $exceptionCsv).Count
if ($writtenExceptionCount -ne $exceptionCount) { throw "Written exception CSV contains $writtenExceptionCount rows; expected $exceptionCount." }
Write-CsvSafe -Rows $crossVersionRows -Path $groupsCsv -Header '"GroupId","TmdbMovieId","CanonicalTitle","InventoryId","Classification","ExistingEdition","SourcePath","DestinationVideoPath","GroupVariants","DuplicateVersion","MultipleCut"'
Write-CsvSafe -Rows $collisionRows -Path $collisionCsv -Header '"CollisionKey","DestinationVideoPath","InventoryId","SourcePath","SourceCollection","Classification","TmdbMovieId","CanonicalTitle","CanonicalReleaseYear","ExistingEdition","Width","Height","SizeBytes","Sha256","PlexRatingKey","PlexLibrary","Disposition"'
Write-CsvSafe -Rows $mediaHealthRows -Path $mediaHealthCsv -Header '"InventoryId","SourcePath","CanonicalTitle","Status","ProbeStatus","ProbeTimedOut","ProbeStderrLineCount","ProbeStderrSummary","Warnings"'
$pathRows = @($planItems | ForEach-Object {
    [pscustomobject]@{ InventoryId = $_.InventoryId; CanonicalTitle = $_.CanonicalTitle; InventoryPath = $_.PathAnalysis.InventoryPath; PlexPath = $_.PathAnalysis.PlexPath; OrdinalIgnoreCaseEqual = $_.PathAnalysis.OrdinalIgnoreCaseEqual; FormCEqual = $_.PathAnalysis.FormCEqual; FormDEqual = $_.PathAnalysis.FormDEqual; ContainsReplacementCharacter = $_.PathAnalysis.ContainsReplacementCharacter; CandidateUnmatchedPlexPaths = ($_.PathAnalysis.CandidateUnmatchedPlexPaths -join ';'); CandidateMatchBasis = $_.PathAnalysis.CandidateMatchBasis; CsvReadEncoding = $_.PathAnalysis.CsvReadEncoding }
})
Write-CsvSafe -Rows $pathRows -Path $pathAnalysisCsv -Header '"InventoryId","CanonicalTitle","InventoryPath","PlexPath","OrdinalIgnoreCaseEqual","FormCEqual","FormDEqual","ContainsReplacementCharacter","CandidateUnmatchedPlexPaths","CandidateMatchBasis","CsvReadEncoding"'
$preflight | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $preflightJson -Encoding UTF8
[ordered]@{ SchemaVersion = 1; PlanningOnly = $true; Items = $rollbackRows } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $rollbackJson -Encoding UTF8
Write-CsvSafe -Rows $rollbackRows -Path $rollbackCsv -Header '"InventoryId","Status","OriginalSourcePath","ProposedDestinationPath","RollbackSourcePath","RollbackDestinationPath","ExpectedSizeBytes","ExpectedSha256","Requirement"'

$summary = [Collections.Generic.List[string]]::new()
$summary.Add('# Reconciled movie migration planning summary')
$summary.Add('')
$summary.Add('Planning only. No file, Plex, Radarr or Docker changes were made.')
$summary.Add('')
$summary.Add("- Source videos: $($manifest.ItemCount)")
$summary.Add("- Ready: $($manifest.ReadyCount)")
$summary.Add("- Review: $($manifest.ReviewCount)")
$summary.Add("- Blocked: $($manifest.BlockedCount)")
$summary.Add("- Exceptions: $($manifest.ExceptionCount) (must equal Review + Blocked)")
$summary.Add("- Destination collision groups: $($manifest.CollisionGroupCount)")
$summary.Add("- Files with media-health warnings: $(@($mediaHealthRows).Count)")
$summary.Add("- Cross-version groups: $($manifest.CrossVersionGroupCount)")
$summary.Add("- Planned source size: $($preflight.PlannedSourceGiB) GiB")
$summary.Add('')
$summary.Add('## Status rules')
$summary.Add('')
$summary.Add('- Ready: confirmed identity, classifiable destination and no detected conflict.')
$summary.Add('- Review: a plan exists, but a Plex/TMDB conflict, collection mismatch, duplicate version, cut distinction or other explicit reason requires a decision.')
$summary.Add('- Blocked: identity/destination is incomplete, a source is missing, an overwrite would occur or destinations collide.')
$summary.Add('- Informational warnings: historical inventory observations retained for audit only; they do not change migration status.')
$summary.Add('- Media-health warnings: ffprobe and stream-health findings reported separately; they do not change migration status by themselves.')
$summary | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$exceptionReport = [Collections.Generic.List[string]]::new()
$exceptionReport.Add('# Migration planning exceptions')
$exceptionReport.Add('')
$exceptionReport.Add('| Status | Source | Proposed destination | Reasons |')
$exceptionReport.Add('| --- | --- | --- | --- |')
foreach ($planItem in @($planItems | Where-Object Status -ne 'Ready')) {
    $reasons = @($planItem.BlockedReasons) + @($planItem.ReviewReasons)
    $exceptionReport.Add("| $($planItem.Status) | $(Escape-Markdown $planItem.SourcePath) | $(Escape-Markdown $planItem.DestinationVideoPath) | $(Escape-Markdown ($reasons -join '; ')) |")
}
$exceptionReport | Set-Content -LiteralPath $exceptionMarkdown -Encoding UTF8

$collisionReport = [Collections.Generic.List[string]]::new()
$collisionReport.Add('# Destination collision evidence')
$collisionReport.Add('')
$collisionReport.Add('Planning only. Every participant remains blocked; this report does not merge, overwrite, rename or assign a different identity.')
$collisionReport.Add('')
$collisionReport.Add('| Destination | TMDB | Title | Source | Class | Dimensions | Size bytes | Hash evidence |')
$collisionReport.Add('| --- | --- | --- | --- | --- | --- | ---: | --- |')
foreach ($row in $collisionRows) {
    $hashEvidence = if ($row.Sha256) { $row.Sha256 } else { 'Not available' }
    $collisionReport.Add("| $(Escape-Markdown $row.DestinationVideoPath) | $($row.TmdbMovieId) | $(Escape-Markdown $row.CanonicalTitle) ($($row.CanonicalReleaseYear)) | $(Escape-Markdown $row.SourcePath) | $($row.Classification) | $($row.Width)x$($row.Height) | $($row.SizeBytes) | $(Escape-Markdown $hashEvidence) |")
}
if (@($collisionRows).Count -eq 0) { $collisionReport.Add('| None |  |  |  |  |  |  |  |') }
$collisionReport | Set-Content -LiteralPath $collisionMarkdown -Encoding UTF8

$mediaHealthReport = [Collections.Generic.List[string]]::new()
$mediaHealthReport.Add('# Media health observations')
$mediaHealthReport.Add('')
$mediaHealthReport.Add('These historical probe findings are retained for follow-up but do not make an otherwise unambiguous migration plan Review or Blocked.')
$mediaHealthReport.Add('')
$mediaHealthReport.Add('| Source | Canonical movie | Probe status | Stderr summary | Planning status | Warnings |')
$mediaHealthReport.Add('| --- | --- | --- | --- | --- | --- |')
foreach ($row in $mediaHealthRows) {
    $mediaHealthReport.Add("| $(Escape-Markdown $row.SourcePath) | $(Escape-Markdown $row.CanonicalTitle) | $(Escape-Markdown $row.ProbeStatus) | $(Escape-Markdown $row.ProbeStderrSummary) | $($row.Status) | $(Escape-Markdown $row.Warnings) |")
}
if (@($mediaHealthRows).Count -eq 0) { $mediaHealthReport.Add('| None |  |  |  |  |  |') }
$mediaHealthReport | Set-Content -LiteralPath $mediaHealthMarkdown -Encoding UTF8

$preflightReport = @(
    '# Migration preflight', '', 'Planning only; rerun every check immediately before any separately approved execution.', '',
    "- Source files present: $($preflight.SourceFilesPresent) / $($preflight.SourceItemCount)",
    "- Source files missing: $($preflight.SourceFilesMissing)",
    "- Destination files already present: $($preflight.DestinationFilesAlreadyPresent)",
    "- Planned source size: $($preflight.PlannedSourceGiB) GiB",
    "- Target drive free space observed: $(if ($null -eq $preflight.TargetDriveFreeGiB) { 'Unavailable' } else { "$($preflight.TargetDriveFreeGiB) GiB" })", '',
    $preflight.StorageNote, '',
    'A future executor must also stop library writers, verify Plex/database backups, disable automatic trash emptying, check destination path casing, recalculate cross-volume space, and verify every copy by size and hash before deleting any source.'
)
$preflightReport | Set-Content -LiteralPath $preflightMarkdown -Encoding UTF8

$plexTransition = @(
    '# Proposed Plex library transition', '', 'Planning guidance only. Nothing in this plan changes Plex.', '',
    '1. Back up the Plex database and metadata directory, and record the current library section IDs, locations, agents and scanner settings.',
    '2. Disable automatic emptying of Plex trash. Freeze Radarr, downloads and other library writers for the approved migration window.',
    '3. Add `Movies\1080p`, `Movies\2160p` and `Movies\3D` as additional locations in the existing Movies library while retaining every old location.',
    '4. Move only a separately approved pilot batch. Scan the existing library so Plex can associate the new paths while old locations remain available.',
    '5. Validate rating keys where possible, watched history, ratings, posters, collections, external IDs, versions, editions, subtitles and direct-play behavior.',
    '6. Keep 1080p and 2160p copies of the same TMDB movie as versions unless they are genuinely different cuts. Keep 3D physically separate; do not assign an edition merely from the unverified SBS assumption.',
    '7. Correct mismatches manually before continuing. Do not proceed while the Blackadder path/encoding exception or any Plex/TMDB identity conflict remains unresolved.',
    '8. After all batches pass validation, remove old library locations. Empty trash only after a final backup and explicit sign-off.', '',
    'Rollback: stop scans and writers, use `rollback-manifest.json` to restore each verified destination to its recorded original path, then restore the Plex database/metadata backup if path association or item metadata was lost. Never run rollback from this planning output without a separately reviewed executor and operation log.'
)
$plexTransition | Set-Content -LiteralPath $plexTransitionPath -Encoding UTF8

Write-Host "Reconciled migration plan complete: $runDirectory"
Write-Host 'Planning only. No files were moved, copied, renamed or deleted, and no services were modified.'
[pscustomobject]@{
    OutputDirectory = $runDirectory; ManifestJson = $manifestJson; ManifestCsv = $manifestCsv; SummaryMarkdown = $summaryPath
    ExceptionCsv = $exceptionCsv; ExceptionMarkdown = $exceptionMarkdown; CrossVersionGroupsCsv = $groupsCsv; PathAnalysisCsv = $pathAnalysisCsv
    CollisionCsv = $collisionCsv; CollisionMarkdown = $collisionMarkdown; MediaHealthCsv = $mediaHealthCsv; MediaHealthMarkdown = $mediaHealthMarkdown
    PreflightJson = $preflightJson; PreflightMarkdown = $preflightMarkdown; RollbackJson = $rollbackJson; RollbackCsv = $rollbackCsv
    PlexTransitionMarkdown = $plexTransitionPath; ItemCount = @($planItems).Count; ReadyCount = $manifest.ReadyCount; ReviewCount = $manifest.ReviewCount; BlockedCount = $manifest.BlockedCount; ExceptionCount = $manifest.ExceptionCount
}

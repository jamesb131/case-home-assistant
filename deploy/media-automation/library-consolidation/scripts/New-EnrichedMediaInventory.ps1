[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InventoryPath,

    [string]$OutputDirectory,

    [string]$CacheDirectory,

    [string]$OverridesPath,

    [string]$TokenEnvironmentVariable = "TMDB_READ_TOKEN",

    [double]$RequestsPerSecond = 3,

    [int]$MaxRetries = 4,

    [string]$TmdbFixturePath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$script:LastTmdbRequestUtc = [datetime]::MinValue

function Get-ObjectProperty {
    param([AllowNull()][object]$Object, [string]$Name, [AllowNull()][object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Get-NormalizedPath {
    param([string]$Path)
    $separators = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd($separators)
}

function Test-PathWithin {
    param([string]$Candidate, [string]$Parent)
    $candidatePath = Get-NormalizedPath $Candidate
    $parentPath = Get-NormalizedPath $Parent
    if ($candidatePath.Equals($parentPath, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $candidatePath.StartsWith("$parentPath$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-StableHash {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Convert-RomanSequel {
    param([string]$Value)
    $map = @{ "ii" = "2"; "iii" = "3"; "iv" = "4"; "v" = "5"; "vi" = "6"; "vii" = "7"; "viii" = "8"; "ix" = "9"; "x" = "10" }
    $parts = @($Value -split ' ' | Where-Object { $_ })
    if (@($parts).Count -gt 0) {
        $last = $parts[@($parts).Count - 1].ToLowerInvariant()
        if ($map.ContainsKey($last)) { $parts[@($parts).Count - 1] = $map[$last] }
    }
    return $parts -join " "
}

function ConvertTo-NormalizedMovieTitle {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $clean = [System.IO.Path]::GetFileNameWithoutExtension($Value)
    $clean = [regex]::Replace($clean, '^\s*\d{1,3}\s*[-._]\s*', '')
    $clean = [regex]::Replace($clean, '\{edition-[^}]+\}', ' ', 'IgnoreCase')
    $clean = [regex]::Replace($clean, '\[[^\]]+\]', ' ')
    $clean = [regex]::Replace($clean, '(?<!\d)(?:19|20)\d{2}(?!\d)', ' ')
    $clean = [regex]::Replace($clean, '\b(2160p|1080p|720p|576p|480p|uhd|bluray|blu-ray|bdrip|brrip|webrip|web-dl|webdl|hdtv|remux|x264|x265|h264|h265|hevc|av1|hdr10\+?|hdr|dolby[ ._-]?vision|dovi|hsbs|sbs|hou|tab|3d)\b', ' ', 'IgnoreCase')
    $clean = $clean -replace '&', ' and '
    $clean = [regex]::Replace($clean, '[^\p{L}\p{Nd}]+', ' ').ToLowerInvariant()
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
    if ($clean -match '^(?<title>.+)\s+the$') { $clean = "the $($Matches['title'])" }
    return Convert-RomanSequel $clean
}

function Get-SourceTitle {
    param([object]$Item)
    $title = "$(Get-ObjectProperty $Item 'Title' '')".Trim()
    if ($title) { return $title }
    $fileName = "$(Get-ObjectProperty $Item 'FileName' '')"
    if ($fileName) { return [System.IO.Path]::GetFileNameWithoutExtension($fileName) }
    return ""
}

function Get-ReleaseYear {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    $match = [regex]::Match("$Value", '^(?<year>\d{4})')
    if ($match.Success) { return [int]$match.Groups['year'].Value }
    return $null
}

function Get-TokenSimilarity {
    param([string]$Left, [string]$Right)
    if (-not $Left -or -not $Right) { return 0.0 }
    if ($Left -eq $Right) { return 1.0 }
    $leftTokens = @($Left -split ' ' | Where-Object { $_ } | Select-Object -Unique)
    $rightTokens = @($Right -split ' ' | Where-Object { $_ } | Select-Object -Unique)
    $intersection = @($leftTokens | Where-Object { $rightTokens -contains $_ }).Count
    $union = @($leftTokens + $rightTokens | Select-Object -Unique).Count
    if ($union -eq 0) { return 0.0 }
    return [math]::Round($intersection / $union, 4)
}

function Get-SequelNumber {
    param([string]$NormalizedTitle)
    $match = [regex]::Match($NormalizedTitle, '(?:^| )(?<number>\d{1,2})$')
    if ($match.Success) { return [int]$match.Groups['number'].Value }
    return $null
}

function Get-CandidateScore {
    param([string]$SourceTitle, [AllowNull()][object]$SourceYear, [object]$Candidate)
    $candidateTitle = ConvertTo-NormalizedMovieTitle "$(Get-ObjectProperty $Candidate 'title' '')"
    $candidateOriginalTitle = ConvertTo-NormalizedMovieTitle "$(Get-ObjectProperty $Candidate 'original_title' '')"
    $titleSimilarity = [math]::Max((Get-TokenSimilarity $SourceTitle $candidateTitle), (Get-TokenSimilarity $SourceTitle $candidateOriginalTitle))
    $exactTitle = [bool]($SourceTitle -and ($SourceTitle -eq $candidateTitle -or $SourceTitle -eq $candidateOriginalTitle))
    $score = if ($exactTitle) { 80.0 } else { $titleSimilarity * 70.0 }
    $reasons = @()
    if ($exactTitle) { $reasons += "Exact normalized title" } else { $reasons += "Title similarity $([math]::Round($titleSimilarity * 100))%" }

    $candidateYear = Get-ReleaseYear (Get-ObjectProperty $Candidate 'release_date')
    $yearConflict = $false
    if ($null -ne $SourceYear -and $null -ne $candidateYear) {
        $difference = [math]::Abs([int]$SourceYear - [int]$candidateYear)
        if ($difference -eq 0) { $score += 20; $reasons += "Release year matches" }
        elseif ($difference -eq 1) { $score += 3; $reasons += "Release year differs by one" }
        else { $score -= 55; $yearConflict = $true; $reasons += "Conflicting release year ($SourceYear vs $candidateYear)" }
    }

    $sourceSequel = Get-SequelNumber $SourceTitle
    $candidateSequel = Get-SequelNumber $candidateTitle
    if ($null -ne $sourceSequel -and $null -ne $candidateSequel -and $sourceSequel -ne $candidateSequel) {
        $score -= 45
        $reasons += "Sequel number conflicts"
    }
    elseif (($null -eq $sourceSequel) -xor ($null -eq $candidateSequel)) {
        $score -= 20
        $reasons += "Sequel number is present on only one title"
    }

    $popularity = [double](Get-ObjectProperty $Candidate 'popularity' 0)
    if ($popularity -gt 0) { $score += [math]::Min(2.0, [math]::Log10($popularity + 1)) }
    return [pscustomobject]@{
        TmdbMovieId = [int](Get-ObjectProperty $Candidate 'id' 0)
        Title = "$(Get-ObjectProperty $Candidate 'title' '')"
        OriginalTitle = "$(Get-ObjectProperty $Candidate 'original_title' '')"
        ReleaseYear = $candidateYear
        ReleaseDate = Get-ObjectProperty $Candidate 'release_date'
        Score = [math]::Round($score, 2)
        TitleSimilarity = $titleSimilarity
        ExactTitle = $exactTitle
        YearConflict = $yearConflict
        Reasons = $reasons
    }
}

function Invoke-TmdbApi {
    param([string]$Uri, [string]$Token, [string]$CachePath, [double]$Rate, [int]$Retries)
    if (Test-Path -LiteralPath $CachePath -PathType Leaf) {
        return Get-Content -LiteralPath $CachePath -Raw | ConvertFrom-Json
    }
    $minimumDelay = if ($Rate -gt 0) { [int][math]::Ceiling(1000 / $Rate) } else { 0 }
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        $elapsed = ((Get-Date).ToUniversalTime() - $script:LastTmdbRequestUtc).TotalMilliseconds
        if ($elapsed -lt $minimumDelay) { Start-Sleep -Milliseconds ([int]($minimumDelay - $elapsed)) }
        try {
            $script:LastTmdbRequestUtc = (Get-Date).ToUniversalTime()
            $response = Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $Token"; Accept = "application/json" } -TimeoutSec 30
            $response | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $CachePath -Encoding UTF8
            return $response
        }
        catch {
            if ($attempt -ge $Retries) { throw }
            Start-Sleep -Seconds ([math]::Min(8, [math]::Pow(2, $attempt - 1)))
        }
    }
}

function Get-TmdbSearch {
    param([string]$Query, [AllowNull()][object]$Fixture, [string]$Token, [string]$CacheRoot, [double]$Rate, [int]$Retries)
    $key = ConvertTo-NormalizedMovieTitle $Query
    if ($Fixture) {
        $searches = Get-ObjectProperty $Fixture 'searches'
        return Get-ObjectProperty $searches $key ([pscustomobject]@{ results = @() })
    }
    $cachePath = Join-Path $CacheRoot ("search-{0}.json" -f (Get-StableHash "search|$key"))
    $uri = "https://api.themoviedb.org/3/search/movie?query=$([uri]::EscapeDataString($Query))&include_adult=false&language=en-US&page=1"
    return Invoke-TmdbApi $uri $Token $cachePath $Rate $Retries
}

function Get-TmdbMovie {
    param([int]$MovieId, [AllowNull()][object]$Fixture, [string]$Token, [string]$CacheRoot, [double]$Rate, [int]$Retries)
    if ($Fixture) {
        $movies = Get-ObjectProperty $Fixture 'movies'
        return Get-ObjectProperty $movies "$MovieId" $null
    }
    $cachePath = Join-Path $CacheRoot "movie-$MovieId.json"
    return Invoke-TmdbApi "https://api.themoviedb.org/3/movie/$MovieId?language=en-US" $Token $cachePath $Rate $Retries
}

function Escape-Markdown {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return "" }
    return "$Value".Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
}

if (-not (Test-Path -LiteralPath $InventoryPath -PathType Leaf)) { throw "Inventory not found: $InventoryPath" }
if ($RequestsPerSecond -le 0 -or $RequestsPerSecond -gt 20) { throw "RequestsPerSecond must be greater than 0 and no more than 20." }
if ($MaxRetries -lt 1 -or $MaxRetries -gt 10) { throw "MaxRetries must be between 1 and 10." }

$resolvedInventoryPath = (Resolve-Path -LiteralPath $InventoryPath).Path
$inventory = Get-Content -LiteralPath $resolvedInventoryPath -Raw | ConvertFrom-Json
$fixture = $null
if ($TmdbFixturePath) {
    if (-not (Test-Path -LiteralPath $TmdbFixturePath -PathType Leaf)) { throw "TMDB fixture not found: $TmdbFixturePath" }
    $fixture = Get-Content -LiteralPath $TmdbFixturePath -Raw | ConvertFrom-Json
}
$token = [Environment]::GetEnvironmentVariable($TokenEnvironmentVariable)
if (-not $fixture -and [string]::IsNullOrWhiteSpace($token)) {
    throw "TMDB API read token is missing. Set the $TokenEnvironmentVariable environment variable for this PowerShell session."
}

$inventoryParent = Split-Path -Parent $resolvedInventoryPath
$reportsParent = Split-Path -Parent $inventoryParent
if (-not $OutputDirectory) { $OutputDirectory = $reportsParent }
if (-not $CacheDirectory) { $CacheDirectory = Join-Path $reportsParent "tmdb-cache" }
foreach ($root in @(Get-ObjectProperty $inventory 'Roots' @())) {
    $rootPath = "$(Get-ObjectProperty $root 'Path' '')"
    if ($rootPath -and ((Test-PathWithin $OutputDirectory $rootPath) -or (Test-PathWithin $CacheDirectory $rootPath))) {
        throw "Output and cache directories must remain outside media roots: $rootPath"
    }
}
New-Item -ItemType Directory -Path $OutputDirectory, $CacheDirectory -Force | Out-Null
$runDirectory = Join-Path (Get-NormalizedPath $OutputDirectory) ("metadata-enrichment-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"))
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

$overrideMap = @{}
if ($OverridesPath) {
    if (-not (Test-Path -LiteralPath $OverridesPath -PathType Leaf)) { throw "Override file not found: $OverridesPath" }
    foreach ($override in @(Import-Csv -LiteralPath $OverridesPath)) {
        $id = "$(Get-ObjectProperty $override 'InventoryId' '')".Trim()
        if (-not $id) { throw "Every override row requires InventoryId." }
        if ($overrideMap.ContainsKey($id)) { throw "Duplicate override for inventory item $id." }
        $overrideMap[$id] = $override
    }
}

$items = @(Get-ObjectProperty $inventory 'Items' @())
$enrichedItems = @()
$index = 0
foreach ($item in $items) {
    $index++
    $sourceTitle = Get-SourceTitle $item
    $normalizedTitle = ConvertTo-NormalizedMovieTitle $sourceTitle
    $sourceYear = Get-ReleaseYear (Get-ObjectProperty $item 'Year')
    $itemFileName = "$(Get-ObjectProperty $item 'FileName' '')"
    Write-Progress -Activity "TMDB movie matching" -Status "[$index/$(@($items).Count)] $itemFileName" -PercentComplete ([math]::Round(($index / [math]::Max(1, @($items).Count)) * 100))
    Write-Host "[$index/$(@($items).Count)] $itemFileName"

    $status = "Unmatched"
    $confirmedId = $null
    $canonicalTitle = $null
    $canonicalYear = $null
    $matchSource = "Automatic"
    $matchReasons = @()
    $candidates = @()
    $apiError = $null

    if ($overrideMap.ContainsKey("$($item.Id)")) {
        $override = $overrideMap["$($item.Id)"]
        $decision = "$(Get-ObjectProperty $override 'Decision' '')".Trim()
        $matchSource = "ManualOverride"
        if ($decision -eq "Confirm") {
            $overrideTmdbId = "$(Get-ObjectProperty $override 'TmdbMovieId' '')".Trim()
            if (-not $overrideTmdbId -or $overrideTmdbId -notmatch '^\d+$') { throw "Confirm override for $($item.Id) requires a numeric TmdbMovieId." }
            $confirmedId = [int]$overrideTmdbId
            $canonicalTitle = "$(Get-ObjectProperty $override 'CanonicalTitle' '')".Trim()
            $overrideYear = "$(Get-ObjectProperty $override 'ReleaseYear' '')".Trim()
            $canonicalYear = if ($overrideYear) { [int]$overrideYear } else { $null }
            if (-not $canonicalTitle -or $null -eq $canonicalYear) {
                $details = Get-TmdbMovie $confirmedId $fixture $token $CacheDirectory $RequestsPerSecond $MaxRetries
                if (-not $details) { throw "Override for $($item.Id) references TMDB $confirmedId but details could not be loaded." }
                if (-not $canonicalTitle) { $canonicalTitle = "$(Get-ObjectProperty $details 'title' '')" }
                if ($null -eq $canonicalYear) { $canonicalYear = Get-ReleaseYear (Get-ObjectProperty $details 'release_date') }
            }
            $status = "HighConfidence"
            $matchReasons += "Explicit manual override"
        }
        elseif ($decision -in @("Unmatched", "Ignore")) {
            $status = "Unmatched"
            $matchReasons += "Explicit manual override: $decision"
        }
        else { throw "Override Decision for $($item.Id) must be Confirm, Unmatched or Ignore." }
    }
    elseif (-not $normalizedTitle) {
        $matchReasons += "No usable title could be derived"
    }
    else {
        try {
            $search = Get-TmdbSearch $normalizedTitle $fixture $token $CacheDirectory $RequestsPerSecond $MaxRetries
            foreach ($candidate in @(Get-ObjectProperty $search 'results' @())) {
                $scored = Get-CandidateScore $normalizedTitle $sourceYear $candidate
                if ($scored.TitleSimilarity -ge 0.45) { $candidates += $scored }
            }
            $candidates = @($candidates | Sort-Object Score -Descending | Select-Object -First 5)
            if (@($candidates).Count -gt 0) {
                $top = $candidates[0]
                $runnerUpScore = if (@($candidates).Count -gt 1) { [double]$candidates[1].Score } else { -100.0 }
                $margin = [double]$top.Score - $runnerUpScore
                $exactTitleCount = @($candidates | Where-Object ExactTitle).Count
                $high = $false
                if ($null -ne $sourceYear) {
                    $high = [bool](-not $top.YearConflict -and $top.TitleSimilarity -ge 0.85 -and $top.Score -ge 88 -and $margin -ge 10)
                }
                else {
                    $high = [bool]($top.ExactTitle -and $exactTitleCount -eq 1 -and $top.Score -ge 80 -and $margin -ge 15)
                }
                if ($high) {
                    $status = "HighConfidence"
                    $confirmedId = $top.TmdbMovieId
                    $canonicalTitle = $top.Title
                    $canonicalYear = $top.ReleaseYear
                    $matchReasons += $top.Reasons
                    $matchReasons += "Candidate margin $([math]::Round($margin, 2))"
                }
                else {
                    $status = "Ambiguous"
                    $matchReasons += "Top candidate did not meet conservative confirmation thresholds"
                    if ($null -eq $sourceYear -and $exactTitleCount -gt 1) { $matchReasons += "Multiple releases share the same normalized title" }
                    if ($top.YearConflict) { $matchReasons += "Top candidate conflicts with the source year" }
                    $matchReasons += "Top score $($top.Score); margin $([math]::Round($margin, 2))"
                }
            }
            else { $matchReasons += "TMDB returned no sufficiently similar movie candidates" }
        }
        catch {
            $status = "ApiError"
            $apiError = $_.Exception.Message
            $matchReasons += "TMDB request failed: $apiError"
        }
    }

    $threeDFormat = Get-ObjectProperty $item 'ThreeDFormat'
    $manualReviewReasons = @()
    if ($status -ne "HighConfidence") { $manualReviewReasons += $matchReasons }
    if ((Get-ObjectProperty $item 'CollectionHint') -eq "3D" -and (-not $threeDFormat -or $threeDFormat -eq "Unknown 3D")) {
        $manualReviewReasons += "3D layout remains unverified; no Plex edition label was suggested"
    }

    $enrichedItems += [pscustomobject]@{
        InventoryId = $item.Id
        OriginalPath = Get-ObjectProperty $item 'FullPath'
        OriginalFileName = $itemFileName
        OriginalTitle = $sourceTitle
        OriginalYear = $sourceYear
        OriginalEdition = Get-ObjectProperty $item 'Edition'
        Collection = Get-ObjectProperty $item 'Collection'
        CollectionHint = Get-ObjectProperty $item 'CollectionHint'
        ResolutionClass = Get-ObjectProperty $item 'ResolutionClass'
        ThreeDFormat = $threeDFormat
        Sha256 = Get-ObjectProperty $item 'Sha256'
        ConfirmedDuplicateGroup = Get-ObjectProperty $item 'ConfirmedDuplicateGroup'
        MatchStatus = $status
        MatchSource = $matchSource
        ConfirmedTmdbMovieId = $confirmedId
        CanonicalTitle = $canonicalTitle
        CanonicalReleaseYear = $canonicalYear
        MatchReasons = @($matchReasons | Select-Object -Unique)
        AlternativeCandidates = $candidates
        ApiError = $apiError
        RequiresManualReview = [bool](@($manualReviewReasons).Count -gt 0)
        ManualReviewReasons = @($manualReviewReasons | Select-Object -Unique)
        OriginalInventoryItem = $item
    }
}
Write-Progress -Activity "TMDB movie matching" -Completed

$confirmedItems = @($enrichedItems | Where-Object { $null -ne $_.ConfirmedTmdbMovieId })
$crossVersionGroups = @($confirmedItems | Group-Object ConfirmedTmdbMovieId | Where-Object Count -gt 1)
$crossVersionRows = @()
foreach ($group in $crossVersionGroups) {
    $groupId = "tmdb-$($group.Name)"
    foreach ($item in $group.Group) {
        $variant = if ($item.CollectionHint -eq "3D") { "3D" } else { $item.ResolutionClass }
        $crossVersionRows += [pscustomobject]@{
            GroupId = $groupId
            TmdbMovieId = $item.ConfirmedTmdbMovieId
            CanonicalTitle = $item.CanonicalTitle
            CanonicalReleaseYear = $item.CanonicalReleaseYear
            InventoryId = $item.InventoryId
            Collection = $item.Collection
            Variant = $variant
            ThreeDFormat = $item.ThreeDFormat
            ExistingEdition = $item.OriginalEdition
            OriginalPath = $item.OriginalPath
            Sha256 = $item.Sha256
            HashConfirmedDuplicate = [bool]($item.ConfirmedDuplicateGroup)
        }
    }
}

$generatedAt = (Get-Date).ToUniversalTime().ToString("o")
$document = [ordered]@{
    SchemaVersion = 1
    GeneratedAtUtc = $generatedAt
    Tool = "New-EnrichedMediaInventory.ps1"
    SourceInventory = $resolvedInventoryPath
    SourceInventorySha256 = (Get-FileHash -LiteralPath $resolvedInventoryPath -Algorithm SHA256).Hash
    ReadOnlySourceInventory = $true
    MatchingPolicy = "Only conservative high-confidence or explicit overrides receive ConfirmedTmdbMovieId"
    ItemCount = @($enrichedItems).Count
    HighConfidenceCount = @($enrichedItems | Where-Object MatchStatus -eq 'HighConfidence').Count
    AmbiguousCount = @($enrichedItems | Where-Object MatchStatus -eq 'Ambiguous').Count
    UnmatchedCount = @($enrichedItems | Where-Object MatchStatus -eq 'Unmatched').Count
    ApiErrorCount = @($enrichedItems | Where-Object MatchStatus -eq 'ApiError').Count
    CrossVersionGroupCount = @($crossVersionGroups).Count
    Items = $enrichedItems
}

$jsonPath = Join-Path $runDirectory "enriched-media-inventory.json"
$csvPath = Join-Path $runDirectory "enriched-media-inventory.csv"
$summaryPath = Join-Path $runDirectory "metadata-matching-summary.md"
$reviewCsvPath = Join-Path $runDirectory "metadata-manual-review.csv"
$reviewMarkdownPath = Join-Path $runDirectory "metadata-manual-review.md"
$groupsPath = Join-Path $runDirectory "cross-version-groups.csv"
$overrideTemplatePath = Join-Path $runDirectory "metadata-overrides.template.csv"
$document | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$csvRows = @($enrichedItems | ForEach-Object {
    $top = if (@($_.AlternativeCandidates).Count -gt 0) { $_.AlternativeCandidates[0] } else { $null }
    [pscustomobject]@{
        InventoryId = $_.InventoryId; OriginalPath = $_.OriginalPath; OriginalFileName = $_.OriginalFileName; OriginalTitle = $_.OriginalTitle; OriginalYear = $_.OriginalYear
        Collection = $_.Collection; ResolutionClass = $_.ResolutionClass; ThreeDFormat = $_.ThreeDFormat; ExistingEdition = $_.OriginalEdition
        MatchStatus = $_.MatchStatus; MatchSource = $_.MatchSource; ConfirmedTmdbMovieId = $_.ConfirmedTmdbMovieId; CanonicalTitle = $_.CanonicalTitle; CanonicalReleaseYear = $_.CanonicalReleaseYear
        SuggestedTmdbMovieId = Get-ObjectProperty $top 'TmdbMovieId'; SuggestedTitle = Get-ObjectProperty $top 'Title'; SuggestedYear = Get-ObjectProperty $top 'ReleaseYear'; SuggestedScore = Get-ObjectProperty $top 'Score'
        RequiresManualReview = $_.RequiresManualReview; ReviewReasons = ($_.ManualReviewReasons -join "; "); ConfirmedDuplicateGroup = $_.ConfirmedDuplicateGroup; Sha256 = $_.Sha256
    }
})
if (@($csvRows).Count -gt 0) { $csvRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 }
else { '"InventoryId","OriginalPath","OriginalFileName","OriginalTitle","OriginalYear","Collection","ResolutionClass","ThreeDFormat","ExistingEdition","MatchStatus","MatchSource","ConfirmedTmdbMovieId","CanonicalTitle","CanonicalReleaseYear","SuggestedTmdbMovieId","SuggestedTitle","SuggestedYear","SuggestedScore","RequiresManualReview","ReviewReasons","ConfirmedDuplicateGroup","Sha256"' | Set-Content -LiteralPath $csvPath -Encoding UTF8 }

$reviewItems = @($enrichedItems | Where-Object RequiresManualReview)
$reviewRows = @($reviewItems | ForEach-Object {
    $alternatives = @($_.AlternativeCandidates | ForEach-Object { "$($_.TmdbMovieId): $($_.Title) ($($_.ReleaseYear)) score=$($_.Score); $($_.Reasons -join ', ')" }) -join " | "
    [pscustomobject]@{ InventoryId = $_.InventoryId; OriginalPath = $_.OriginalPath; OriginalTitle = $_.OriginalTitle; OriginalYear = $_.OriginalYear; MatchStatus = $_.MatchStatus; Reasons = ($_.ManualReviewReasons -join "; "); Alternatives = $alternatives }
})
if (@($reviewRows).Count -gt 0) { $reviewRows | Export-Csv -LiteralPath $reviewCsvPath -NoTypeInformation -Encoding UTF8 }
else { '"InventoryId","OriginalPath","OriginalTitle","OriginalYear","MatchStatus","Reasons","Alternatives"' | Set-Content -LiteralPath $reviewCsvPath -Encoding UTF8 }

if (@($crossVersionRows).Count -gt 0) { $crossVersionRows | Export-Csv -LiteralPath $groupsPath -NoTypeInformation -Encoding UTF8 }
else { '"GroupId","TmdbMovieId","CanonicalTitle","CanonicalReleaseYear","InventoryId","Collection","Variant","ThreeDFormat","ExistingEdition","OriginalPath","Sha256","HashConfirmedDuplicate"' | Set-Content -LiteralPath $groupsPath -Encoding UTF8 }

$overrideRows = @($reviewItems | ForEach-Object {
    $top = if (@($_.AlternativeCandidates).Count -gt 0) { $_.AlternativeCandidates[0] } else { $null }
    [pscustomobject]@{ InventoryId = $_.InventoryId; Decision = ""; TmdbMovieId = Get-ObjectProperty $top 'TmdbMovieId'; CanonicalTitle = Get-ObjectProperty $top 'Title'; ReleaseYear = Get-ObjectProperty $top 'ReleaseYear'; Notes = "" }
})
if (@($overrideRows).Count -gt 0) { $overrideRows | Export-Csv -LiteralPath $overrideTemplatePath -NoTypeInformation -Encoding UTF8 }
else { '"InventoryId","Decision","TmdbMovieId","CanonicalTitle","ReleaseYear","Notes"' | Set-Content -LiteralPath $overrideTemplatePath -Encoding UTF8 }

$summary = [System.Collections.Generic.List[string]]::new()
$summary.Add("# Metadata matching summary")
$summary.Add("")
$summary.Add("Generated: $generatedAt")
$summary.Add("")
$summary.Add("Read-only enrichment of: $resolvedInventoryPath")
$summary.Add("")
$summary.Add("- Items: $(@($enrichedItems).Count)")
$summary.Add("- High-confidence or manually confirmed: $($document.HighConfidenceCount)")
$summary.Add("- Ambiguous: $($document.AmbiguousCount)")
$summary.Add("- Unmatched: $($document.UnmatchedCount)")
$summary.Add("- API errors: $($document.ApiErrorCount)")
$summary.Add("- Manual review: $(@($reviewItems).Count)")
$summary.Add("- Cross-version TMDB groups: $(@($crossVersionGroups).Count)")
$summary.Add("")
$summary.Add("A top-ranked result is not confirmation. Ambiguous items have no confirmed TMDB ID and are excluded from cross-version groups.")
$summary | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$reviewMarkdown = [System.Collections.Generic.List[string]]::new()
$reviewMarkdown.Add("# Metadata manual review")
$reviewMarkdown.Add("")
$reviewMarkdown.Add("| Inventory ID | Original | Status | Reasons | Alternatives |")
$reviewMarkdown.Add("| --- | --- | --- | --- | --- |")
foreach ($row in $reviewRows) { $reviewMarkdown.Add("| $($row.InventoryId) | $(Escape-Markdown $row.OriginalTitle) | $($row.MatchStatus) | $(Escape-Markdown $row.Reasons) | $(Escape-Markdown $row.Alternatives) |") }
$reviewMarkdown | Set-Content -LiteralPath $reviewMarkdownPath -Encoding UTF8

Write-Host "Metadata enrichment complete: $runDirectory"
Write-Host "No media, Plex or automation configuration was modified."
[pscustomobject]@{ OutputDirectory = $runDirectory; EnrichedJson = $jsonPath; EnrichedCsv = $csvPath; SummaryMarkdown = $summaryPath; ManualReviewCsv = $reviewCsvPath; ManualReviewMarkdown = $reviewMarkdownPath; CrossVersionGroupsCsv = $groupsPath; OverrideTemplateCsv = $overrideTemplatePath; ItemCount = @($enrichedItems).Count }

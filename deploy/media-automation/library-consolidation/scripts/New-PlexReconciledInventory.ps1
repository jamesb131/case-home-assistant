[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EnrichedInventoryPath,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [string]$PlexTokenEnvironmentVariable = "PLEX_TOKEN",

    [string]$TmdbTokenEnvironmentVariable = "TMDB_READ_TOKEN",

    [int]$MaxRetries = 4,

    [double]$TmdbRequestsPerSecond = 3,

    [string]$PlexFixturePath,

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

function Get-PlexCollectionItems {
    param([AllowNull()][object]$Container, [string[]]$PropertyNames)
    foreach ($propertyName in $PropertyNames) {
        $value = Get-ObjectProperty $Container $propertyName $null
        if ($null -ne $value) { return @($value) }
    }
    return @()
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

function Get-ReleaseYear {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    $match = [regex]::Match("$Value", '^(?<year>\d{4})')
    if ($match.Success) { return [int]$match.Groups['year'].Value }
    return $null
}

function ConvertTo-PathKey {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $value = $Path.Trim().Trim('"').Replace('/', '\')
    if ($value.StartsWith('\\?\')) { $value = $value.Substring(4) }
    $isUnc = $value.StartsWith('\\')
    $value = [regex]::Replace($value, '\\+', '\')
    if ($isUnc) { $value = "\$value" }
    $prefix = ""
    $minimumDepth = 0
    if ($value -match '^(?<drive>[A-Za-z]:)\\') {
        $prefix = "$($Matches['drive'].ToLowerInvariant())\"
        $value = $value.Substring(3)
    }
    elseif ($value.StartsWith('\\')) {
        $prefix = '\\'
        $minimumDepth = 2
        $value = $value.Substring(2)
    }
    elseif ($value.StartsWith('\')) {
        $prefix = '\'
        $value = $value.Substring(1)
    }
    $segments = New-Object 'System.Collections.Generic.List[string]'
    foreach ($segment in @($value -split '\\' | Where-Object { $_ -and $_ -ne '.' })) {
        if ($segment -eq '..') {
            if ($segments.Count -gt $minimumDepth) { $segments.RemoveAt($segments.Count - 1) }
            elseif (-not $prefix) { $segments.Add($segment) }
        }
        else { $segments.Add($segment) }
    }
    $result = "$prefix$($segments -join '\')"
    if ($result -eq $prefix) { return $result.ToLowerInvariant() }
    return $result.TrimEnd('\').ToLowerInvariant()
}

function Test-AbsolutePortablePath {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $value = $Path.Trim().Trim('"')
    return [bool]($value -match '^[A-Za-z]:[\\/]' -or $value -match '^[\\/]{2}[^\\/]' -or $value -match '^/')
}

function Test-PathPrefix {
    param([string]$PathKey, [string]$PrefixKey)
    if (-not $PathKey -or -not $PrefixKey) { return $false }
    return [bool]($PathKey -eq $PrefixKey -or $PathKey.StartsWith("$PrefixKey\", [System.StringComparison]::OrdinalIgnoreCase))
}

function Convert-PlexPath {
    param([string]$Path, [object[]]$Mappings)
    $pathKey = ConvertTo-PathKey $Path
    foreach ($mapping in @($Mappings | Sort-Object { (ConvertTo-PathKey (Get-ObjectProperty $_ 'plexPrefix' '')).Length } -Descending)) {
        $plexPrefix = ConvertTo-PathKey "$(Get-ObjectProperty $mapping 'plexPrefix' '')"
        $inventoryPrefix = ConvertTo-PathKey "$(Get-ObjectProperty $mapping 'inventoryPrefix' '')"
        if (-not $plexPrefix -or -not $inventoryPrefix) { continue }
        if (Test-PathPrefix $pathKey $plexPrefix) {
            $suffix = $pathKey.Substring($plexPrefix.Length).TrimStart('\')
            $mapped = if ($suffix) { "$inventoryPrefix\$suffix" } else { $inventoryPrefix }
            return [pscustomobject]@{ OriginalPath = $Path; NormalizedPlexPath = $pathKey; InventoryPathKey = $mapped; MappingApplied = $true }
        }
    }
    return [pscustomobject]@{ OriginalPath = $Path; NormalizedPlexPath = $pathKey; InventoryPathKey = $pathKey; MappingApplied = $false }
}

function Test-OutputOutsideMediaRoots {
    param([string]$Candidate, [object[]]$Items)
    $candidateKey = ConvertTo-PathKey $Candidate
    foreach ($item in $Items) {
        $original = Get-ObjectProperty $item 'OriginalInventoryItem'
        $rootKey = ConvertTo-PathKey "$(Get-ObjectProperty $original 'RootPath' '')"
        if ($rootKey -and (Test-PathPrefix $candidateKey $rootKey)) { throw "Output and cache directories must remain outside media roots: $rootKey" }
    }
}

function Invoke-JsonGet {
    param([string]$Uri, [hashtable]$Headers, [int]$Retries)
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try { return Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -TimeoutSec 30 }
        catch {
            if ($attempt -ge $Retries) { throw }
            Start-Sleep -Seconds ([math]::Min(8, [math]::Pow(2, $attempt - 1)))
        }
    }
}

function Get-PlexContainer {
    param([string]$BaseUrl, [string]$PathAndQuery, [string]$Token, [AllowNull()][object]$Fixture, [string]$FixtureKind, [AllowNull()][object]$FixtureKey, [int]$PageSize, [int]$Offset, [int]$Retries)
    if ($Fixture) {
        if ($FixtureKind -eq 'Sections') {
            return [pscustomobject]@{ Directory = @(Get-ObjectProperty $Fixture 'sections' @()); size = @(Get-ObjectProperty $Fixture 'sections' @()).Count; totalSize = @(Get-ObjectProperty $Fixture 'sections' @()).Count; offset = 0 }
        }
        if ($FixtureKind -eq 'SectionPage') {
            $sectionItems = @(Get-ObjectProperty (Get-ObjectProperty $Fixture 'sectionItems') "$FixtureKey" @())
            $page = @($sectionItems | Select-Object -Skip $Offset -First $PageSize)
            $reportedTotals = Get-ObjectProperty $Fixture 'sectionReportedTotals' $null
            $reportedTotal = if ($reportedTotals) { Get-ObjectProperty $reportedTotals "$FixtureKey" @($sectionItems).Count } else { @($sectionItems).Count }
            $metadata = if ((Get-ObjectProperty $Fixture 'scalarSingleItemResponses' $false) -and @($page).Count -eq 1) { $page[0] } else { $page }
            return [pscustomobject]@{ Metadata = $metadata; size = @($page).Count; totalSize = $reportedTotal; offset = $Offset }
        }
        if ($FixtureKind -eq 'Metadata') {
            $details = Get-ObjectProperty $Fixture 'details'
            $detail = Get-ObjectProperty $details "$FixtureKey" $null
            return [pscustomobject]@{ Metadata = if ($detail) { @($detail) } else { @() }; size = if ($detail) { 1 } else { 0 }; totalSize = if ($detail) { 1 } else { 0 }; offset = 0 }
        }
    }
    $headers = @{ 'X-Plex-Token' = $Token; Accept = 'application/json'; 'X-Plex-Container-Start' = "$Offset"; 'X-Plex-Container-Size' = "$PageSize" }
    $requestPath = $PathAndQuery
    if ($FixtureKind -eq 'SectionPage') {
        $separator = if ($requestPath.Contains('?')) { '&' } else { '?' }
        $requestPath = "${requestPath}${separator}X-Plex-Container-Start=$Offset&X-Plex-Container-Size=$PageSize"
    }
    $response = Invoke-JsonGet -Uri "$($BaseUrl.TrimEnd('/'))$requestPath" -Headers $headers -Retries $Retries
    return Get-ObjectProperty $response 'MediaContainer' $response
}

function Get-PlexExternalIds {
    param([object]$Movie)
    $values = @()
    foreach ($guid in @(Get-ObjectProperty $Movie 'Guid' @())) {
        $id = "$(Get-ObjectProperty $guid 'id' '')".Trim()
        if ($id) { $values += $id }
    }
    foreach ($name in @('guid', 'GuidString')) {
        $value = "$(Get-ObjectProperty $Movie $name '')".Trim()
        if ($value) { $values += $value }
    }
    $values = @($values | Select-Object -Unique)
    $tmdbIds = @()
    $imdbIds = @()
    foreach ($value in $values) {
        $tmdbMatch = [regex]::Match($value, '(?i)(?:tmdb|themoviedb)://(?<id>\d+)')
        if (-not $tmdbMatch.Success) { $tmdbMatch = [regex]::Match($value, '(?i)com\.plexapp\.agents\.themoviedb://(?<id>\d+)') }
        if ($tmdbMatch.Success) { $tmdbIds += [int]$tmdbMatch.Groups['id'].Value }
        $imdbMatch = [regex]::Match($value, '(?i)(?:imdb://|com\.plexapp\.agents\.imdb://)(?<id>tt\d+)')
        if ($imdbMatch.Success) { $imdbIds += $imdbMatch.Groups['id'].Value.ToLowerInvariant() }
    }
    return [pscustomobject]@{ GuidValues = $values; TmdbIds = @($tmdbIds | Select-Object -Unique); ImdbIds = @($imdbIds | Select-Object -Unique) }
}

function Get-PlexPartPaths {
    param([object]$Movie)
    $paths = @()
    foreach ($media in @(Get-ObjectProperty $Movie 'Media' @())) {
        foreach ($part in @(Get-ObjectProperty $media 'Part' @())) {
            $file = "$(Get-ObjectProperty $part 'file' '')".Trim()
            if ($file) { $paths += $file }
        }
    }
    return @($paths | Select-Object -Unique)
}

function Resolve-ImdbThroughTmdb {
    param([string]$ImdbId, [AllowNull()][object]$Fixture, [string]$Token, [string]$CacheRoot, [double]$Rate, [int]$Retries)
    if ($Fixture) {
        $findResults = Get-ObjectProperty $Fixture 'find'
        return Get-ObjectProperty $findResults $ImdbId ([pscustomobject]@{ movie_results = @() })
    }
    $cachePath = Join-Path $CacheRoot ("find-imdb-{0}.json" -f (Get-StableHash $ImdbId))
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) { return Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json }
    if ([string]::IsNullOrWhiteSpace($Token)) { throw "TMDB API read token is required to resolve Plex IMDb ID $ImdbId." }
    $minimumDelay = [int][math]::Ceiling(1000 / $Rate)
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        $elapsed = ((Get-Date).ToUniversalTime() - $script:LastTmdbRequestUtc).TotalMilliseconds
        if ($elapsed -lt $minimumDelay) { Start-Sleep -Milliseconds ([int]($minimumDelay - $elapsed)) }
        try {
            $script:LastTmdbRequestUtc = (Get-Date).ToUniversalTime()
            $uri = "https://api.themoviedb.org/3/find/$([uri]::EscapeDataString($ImdbId))?external_source=imdb_id&language=en-US"
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $Token"; Accept = 'application/json' } -TimeoutSec 30
            $response | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $cachePath -Encoding UTF8
            return $response
        }
        catch {
            if ($attempt -ge $Retries) { throw }
            Start-Sleep -Seconds ([math]::Min(8, [math]::Pow(2, $attempt - 1)))
        }
    }
}

function Escape-Markdown {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return "" }
    return "$Value".Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

if (-not (Test-Path -LiteralPath $EnrichedInventoryPath -PathType Leaf)) { throw "Enriched inventory not found: $EnrichedInventoryPath" }
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Plex reconciliation configuration not found: $ConfigPath" }
if ($MaxRetries -lt 1 -or $MaxRetries -gt 10) { throw "MaxRetries must be between 1 and 10." }
if ($TmdbRequestsPerSecond -le 0 -or $TmdbRequestsPerSecond -gt 20) { throw "TmdbRequestsPerSecond must be greater than 0 and no more than 20." }

$resolvedInventoryPath = (Resolve-Path -LiteralPath $EnrichedInventoryPath).Path
$config = Get-Content -LiteralPath (Resolve-Path -LiteralPath $ConfigPath).Path -Raw | ConvertFrom-Json
$enriched = Get-Content -LiteralPath $resolvedInventoryPath -Raw | ConvertFrom-Json
$items = @(Get-ObjectProperty $enriched 'Items' @())
$plexBaseUrl = "$(Get-ObjectProperty $config 'plexBaseUrl' '')".Trim().TrimEnd('/')
try { $plexBaseUri = [uri]$plexBaseUrl } catch { throw "plexBaseUrl must be a valid absolute URL." }
if (-not $plexBaseUri.IsAbsoluteUri -or $plexBaseUri.Scheme -notin @('http', 'https')) { throw "plexBaseUrl must be an http:// or https:// URL." }
if ($plexBaseUri.UserInfo -or $plexBaseUri.Query -or $plexBaseUri.Fragment) { throw "Do not place credentials, query parameters or fragments in plexBaseUrl. Supply the Plex token only through the environment variable." }
$pageSize = [int](Get-ObjectProperty $config 'pageSize' 200)
if ($pageSize -lt 1 -or $pageSize -gt 1000) { throw "pageSize must be between 1 and 1000." }
$outputDirectory = "$(Get-ObjectProperty $config 'outputDirectory' '')".Trim()
$cacheDirectory = "$(Get-ObjectProperty $config 'cacheDirectory' '')".Trim()
if (-not $outputDirectory) { $outputDirectory = Split-Path -Parent (Split-Path -Parent $resolvedInventoryPath) }
if (-not $cacheDirectory) { $cacheDirectory = Join-Path $outputDirectory 'tmdb-cache' }
$pathMappings = @(Get-ObjectProperty $config 'pathMappings' @())
foreach ($mapping in $pathMappings) {
    $plexPrefixValue = "$(Get-ObjectProperty $mapping 'plexPrefix' '')".Trim()
    $inventoryPrefixValue = "$(Get-ObjectProperty $mapping 'inventoryPrefix' '')".Trim()
    if (-not $plexPrefixValue -or -not $inventoryPrefixValue) { throw "Every path mapping requires plexPrefix and inventoryPrefix." }
    if (-not (Test-AbsolutePortablePath $plexPrefixValue) -or -not (Test-AbsolutePortablePath $inventoryPrefixValue)) { throw "Path mapping prefixes must be absolute paths." }
}
Test-OutputOutsideMediaRoots -Candidate $outputDirectory -Items $items
Test-OutputOutsideMediaRoots -Candidate $cacheDirectory -Items $items

$plexFixture = $null
if ($PlexFixturePath) { $plexFixture = Get-Content -LiteralPath $PlexFixturePath -Raw | ConvertFrom-Json }
$tmdbFixture = $null
if ($TmdbFixturePath) { $tmdbFixture = Get-Content -LiteralPath $TmdbFixturePath -Raw | ConvertFrom-Json }
$plexToken = [Environment]::GetEnvironmentVariable($PlexTokenEnvironmentVariable)
if (-not $plexFixture -and [string]::IsNullOrWhiteSpace($plexToken)) { throw "Plex token is missing. Set the $PlexTokenEnvironmentVariable environment variable for this PowerShell session." }
$tmdbToken = [Environment]::GetEnvironmentVariable($TmdbTokenEnvironmentVariable)

New-Item -ItemType Directory -Path $outputDirectory, $cacheDirectory -Force | Out-Null
$runDirectory = Join-Path $outputDirectory ("plex-reconciliation-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

$sectionsContainer = Get-PlexContainer -BaseUrl $plexBaseUrl -PathAndQuery '/library/sections' -Token $plexToken -Fixture $plexFixture -FixtureKind 'Sections' -FixtureKey $null -PageSize $pageSize -Offset 0 -Retries $MaxRetries
$movieSections = @(Get-PlexCollectionItems -Container $sectionsContainer -PropertyNames @('Directory') | Where-Object { "$(Get-ObjectProperty $_ 'type' '')" -eq 'movie' })
if (@($movieSections).Count -eq 0) { throw 'Plex returned no movie libraries. Reconciliation cannot continue.' }
$plexMovies = @()
$libraryDiagnostics = @()
foreach ($section in $movieSections) {
    $sectionKey = "$(Get-ObjectProperty $section 'key' '')"
    $sectionTitle = "$(Get-ObjectProperty $section 'title' '')"
    if ([string]::IsNullOrWhiteSpace($sectionKey)) { throw "Plex returned a movie library without a section key: $sectionTitle" }
    $offset = 0
    $reportedTotal = $null
    $sectionMovies = @()
    $seenRatingKeys = @{}
    $pageNumber = 0
    do {
        $pageNumber++
        if ($pageNumber -gt 10000) { throw "Plex pagination exceeded the safety limit for library '$sectionTitle' (section $sectionKey)." }
        $container = Get-PlexContainer -BaseUrl $plexBaseUrl -PathAndQuery "/library/sections/$sectionKey/all?type=1&includeGuids=1" -Token $plexToken -Fixture $plexFixture -FixtureKind 'SectionPage' -FixtureKey $sectionKey -PageSize $pageSize -Offset $offset -Retries $MaxRetries
        $pageItems = @(Get-PlexCollectionItems -Container $container -PropertyNames @('Metadata', 'Video'))
        $returned = @($pageItems).Count
        $responseOffsetValue = Get-ObjectProperty $container 'offset' $null
        if ($null -ne $responseOffsetValue -and [int]$responseOffsetValue -ne $offset) {
            throw "Incomplete Plex enumeration for library '$sectionTitle' (section $sectionKey): requested offset $offset but Plex returned offset $responseOffsetValue."
        }
        $responseSizeValue = Get-ObjectProperty $container 'size' $null
        if ($null -ne $responseSizeValue -and [int]$responseSizeValue -ne $returned) {
            throw "Incomplete Plex enumeration for library '$sectionTitle' (section $sectionKey): Plex reported page size $responseSizeValue but $returned records were parsed."
        }
        $totalValue = Get-ObjectProperty $container 'totalSize' $null
        if ($null -ne $totalValue) {
            if ($null -eq $reportedTotal) { $reportedTotal = [int]$totalValue }
            elseif ([int]$totalValue -ne $reportedTotal) { throw "Plex changed the reported total for library '$sectionTitle' (section $sectionKey) from $reportedTotal to $totalValue during pagination." }
        }
        if ($returned -eq 0) {
            if ($null -ne $reportedTotal -and $offset -lt $reportedTotal) {
                throw "Incomplete Plex enumeration for library '$sectionTitle' (section $sectionKey): Plex reported $reportedTotal records but returned an empty page at offset $offset."
            }
            break
        }
        foreach ($listMovie in $pageItems) {
            $movie = $listMovie
            $listTitle = "$(Get-ObjectProperty $listMovie 'title' '')"
            $listYear = Get-ReleaseYear (Get-ObjectProperty $listMovie 'year')
            $detailLookupError = $null
            $ratingKey = "$(Get-ObjectProperty $movie 'ratingKey' '')"
            if ([string]::IsNullOrWhiteSpace($ratingKey)) { throw "Plex returned a movie without a rating key in library '$sectionTitle' (section $sectionKey) at offset $offset." }
            if ($seenRatingKeys.ContainsKey($ratingKey)) {
                throw "Incomplete Plex enumeration for library '$sectionTitle' (section $sectionKey): rating key $ratingKey was returned more than once. Plex may have repeated a page."
            }
            $seenRatingKeys[$ratingKey] = $true
            $externalIds = Get-PlexExternalIds $movie
            $partPaths = @(Get-PlexPartPaths $movie)
            if ($ratingKey -and ((@($externalIds.TmdbIds).Count -eq 0 -and @($externalIds.ImdbIds).Count -eq 0) -or @($partPaths).Count -eq 0)) {
                try {
                    $detailContainer = Get-PlexContainer -BaseUrl $plexBaseUrl -PathAndQuery "/library/metadata/${ratingKey}?includeGuids=1" -Token $plexToken -Fixture $plexFixture -FixtureKind 'Metadata' -FixtureKey $ratingKey -PageSize 1 -Offset 0 -Retries $MaxRetries
                    $details = @(Get-PlexCollectionItems -Container $detailContainer -PropertyNames @('Metadata', 'Video'))
                    if (@($details).Count -eq 1) {
                        $movie = $details[0]
                        $detailIds = Get-PlexExternalIds $movie
                        $externalIds = [pscustomobject]@{
                            GuidValues = @(@($externalIds.GuidValues) + @($detailIds.GuidValues) | Select-Object -Unique)
                            TmdbIds = @(@($externalIds.TmdbIds) + @($detailIds.TmdbIds) | Select-Object -Unique)
                            ImdbIds = @(@($externalIds.ImdbIds) + @($detailIds.ImdbIds) | Select-Object -Unique)
                        }
                        $partPaths = @(@($partPaths) + @(Get-PlexPartPaths $movie) | Select-Object -Unique)
                    }
                }
                catch { $detailLookupError = $_.Exception.Message }
            }
            $sectionMovies += [pscustomobject]@{
                RatingKey = $ratingKey
                LibraryKey = $sectionKey
                LibraryTitle = $sectionTitle
                Title = "$(Get-ObjectProperty $movie 'title' $listTitle)"
                Year = Get-ReleaseYear (Get-ObjectProperty $movie 'year' $listYear)
                GuidValues = @($externalIds.GuidValues)
                TmdbIds = @($externalIds.TmdbIds)
                ImdbIds = @($externalIds.ImdbIds)
                PartPaths = @($partPaths)
                DetailLookupError = $detailLookupError
            }
        }
        $offset += $returned
        if ($null -ne $reportedTotal -and $offset -gt $reportedTotal) {
            throw "Incomplete Plex enumeration for library '$sectionTitle' (section $sectionKey): retrieved $offset records, exceeding Plex's reported total of $reportedTotal."
        }
        $hasMore = if ($null -ne $reportedTotal) { $offset -lt $reportedTotal } else { $returned -eq $pageSize }
    } while ($hasMore)
    if ($null -ne $reportedTotal -and @($sectionMovies).Count -ne $reportedTotal) {
        throw "Incomplete Plex enumeration for library '$sectionTitle' (section $sectionKey): Plex reported $reportedTotal records but $(@($sectionMovies).Count) were retrieved."
    }
    $sectionPartCount = 0
    foreach ($sectionMovie in @($sectionMovies)) { $sectionPartCount += @($sectionMovie.PartPaths).Count }
    $plexMovies += @($sectionMovies)
    $libraryDiagnostics += [pscustomobject]@{
        SectionKey = $sectionKey
        LibraryTitle = $sectionTitle
        PlexReportedRecords = $reportedTotal
        RecordsRetrieved = @($sectionMovies).Count
        MediaPartsRetrieved = $sectionPartCount
        PathsMatchedToInventory = 0
    }
}

$plexPartsByPath = @{}
$allPlexParts = @()
foreach ($movie in $plexMovies) {
    foreach ($partPath in @($movie.PartPaths)) {
        $converted = Convert-PlexPath -Path $partPath -Mappings $pathMappings
        $partRecord = [pscustomobject]@{ Movie = $movie; PlexPath = $partPath; InventoryPathKey = $converted.InventoryPathKey; MappingApplied = $converted.MappingApplied }
        $allPlexParts += $partRecord
        if (-not $plexPartsByPath.ContainsKey($converted.InventoryPathKey)) { $plexPartsByPath[$converted.InventoryPathKey] = @() }
        $plexPartsByPath[$converted.InventoryPathKey] = @($plexPartsByPath[$converted.InventoryPathKey]) + $partRecord
    }
}

$inventoryItemsByPath = @{}
foreach ($item in $items) {
    $inventoryPath = "$(Get-ObjectProperty $item 'OriginalPath' '')"
    $key = if (Test-AbsolutePortablePath $inventoryPath) { ConvertTo-PathKey $inventoryPath } else { "invalid::$((Get-ObjectProperty $item 'InventoryId' ''))" }
    if (-not $inventoryItemsByPath.ContainsKey($key)) { $inventoryItemsByPath[$key] = @() }
    $inventoryItemsByPath[$key] = @($inventoryItemsByPath[$key]) + $item
}

foreach ($diagnostic in $libraryDiagnostics) {
    $matchedPathKeys = @(
        $allPlexParts |
            Where-Object { $_.Movie.LibraryKey -eq $diagnostic.SectionKey -and $inventoryItemsByPath.ContainsKey($_.InventoryPathKey) } |
            ForEach-Object { $_.InventoryPathKey } |
            Select-Object -Unique
    )
    $diagnostic.PathsMatchedToInventory = @($matchedPathKeys).Count
}

$reconciledItems = @()
$reviewRows = @()
$index = 0
foreach ($item in $items) {
    $index++
    $inventoryId = "$(Get-ObjectProperty $item 'InventoryId' '')"
    $originalPath = "$(Get-ObjectProperty $item 'OriginalPath' '')"
    $pathKey = ConvertTo-PathKey $originalPath
    Write-Progress -Activity 'Reconciling Plex metadata' -Status "[$index/$(@($items).Count)] $originalPath" -PercentComplete ([math]::Round(($index / [math]::Max(1, @($items).Count)) * 100))
    Write-Host "[$index/$(@($items).Count)] $originalPath"

    $previousIdValue = "$(Get-ObjectProperty $item 'ConfirmedTmdbMovieId' '')".Trim()
    $previousId = if ($previousIdValue -match '^\d+$' -and [int]$previousIdValue -gt 0) { [int]$previousIdValue } else { $null }
    $resolvedId = $previousId
    $canonicalTitle = Get-ObjectProperty $item 'CanonicalTitle'
    $canonicalYear = Get-ObjectProperty $item 'CanonicalReleaseYear'
    $identificationSource = if ($null -ne $previousId) { 'TMDBEnrichment' } else { 'Unresolved' }
    $issues = @()
    $plexRatingKey = $null
    $plexLibrary = $null
    $plexTitle = $null
    $plexYear = $null
    $plexPath = $null
    $plexGuidValues = @()
    $plexTmdbIds = @()
    $plexImdbIds = @()
    $pathMatchCount = 0

    if (-not (Test-AbsolutePortablePath $originalPath)) { $issues += 'InventoryPathNotAbsolute' }
    if (@($inventoryItemsByPath[$pathKey]).Count -gt 1) { $issues += 'DuplicateInventoryPath' }
    $pathMatches = if ($plexPartsByPath.ContainsKey($pathKey)) { @($plexPartsByPath[$pathKey]) } else { @() }
    $distinctRatingKeys = @($pathMatches | ForEach-Object { $_.Movie.RatingKey } | Select-Object -Unique)
    $pathMatchCount = @($distinctRatingKeys).Count
    if ($pathMatchCount -gt 1) {
        $issues += 'DuplicatePlexFileMappings'
    }
    elseif ($pathMatchCount -eq 1 -and -not ($issues -contains 'DuplicateInventoryPath')) {
        $match = @($pathMatches | Where-Object { $_.Movie.RatingKey -eq $distinctRatingKeys[0] })[0]
        $plexMovie = $match.Movie
        $plexRatingKey = $plexMovie.RatingKey
        $plexLibrary = $plexMovie.LibraryTitle
        $plexTitle = $plexMovie.Title
        $plexYear = $plexMovie.Year
        $plexPath = $match.PlexPath
        $plexGuidValues = @($plexMovie.GuidValues)
        $plexTmdbIds = @($plexMovie.TmdbIds)
        $plexImdbIds = @($plexMovie.ImdbIds)
        if (Get-ObjectProperty $plexMovie 'DetailLookupError') { $issues += 'PlexDetailLookupFailed' }
        if (@($plexTmdbIds).Count -eq 1) {
            $resolvedId = [int]$plexTmdbIds[0]
            $canonicalTitle = $plexTitle
            $canonicalYear = $plexYear
            $identificationSource = 'PlexTMDB'
        }
        elseif (@($plexTmdbIds).Count -gt 1) {
            $issues += 'MultiplePlexTmdbIds'
        }
        elseif (@($plexImdbIds).Count -eq 1) {
            try {
                $findResult = Resolve-ImdbThroughTmdb -ImdbId $plexImdbIds[0] -Fixture $tmdbFixture -Token $tmdbToken -CacheRoot $cacheDirectory -Rate $TmdbRequestsPerSecond -Retries $MaxRetries
                $movies = @(Get-ObjectProperty $findResult 'movie_results' @())
                if (@($movies).Count -eq 1) {
                    $tmdbMovieId = [int](Get-ObjectProperty $movies[0] 'id' 0)
                    if ($tmdbMovieId -gt 0) {
                        $resolvedId = $tmdbMovieId
                        $canonicalTitle = "$(Get-ObjectProperty $movies[0] 'title' $plexTitle)"
                        $canonicalYear = Get-ReleaseYear (Get-ObjectProperty $movies[0] 'release_date' $plexYear)
                        $identificationSource = 'PlexIMDb'
                    }
                    else { $issues += 'ImdbResolutionMissingTmdbId' }
                }
                elseif (@($movies).Count -eq 0) { $issues += 'ImdbIdNotFoundInTmdb' }
                else { $issues += 'ImdbIdAmbiguousInTmdb' }
            }
            catch { $issues += 'ImdbResolutionFailed' }
        }
        elseif (@($plexImdbIds).Count -gt 1) {
            $issues += 'MultiplePlexImdbIds'
        }
        else {
            $issues += 'MissingPlexExternalIds'
        }
        if ($identificationSource -in @('PlexTMDB', 'PlexIMDb') -and $null -ne $previousId -and [int]$previousId -ne [int]$resolvedId) { $issues += 'PlexTmdbConflict' }
    }

    if ($identificationSource -eq 'Unresolved') { $issues += 'Unresolved' }
    $threeDFormat = "$(Get-ObjectProperty $item 'ThreeDFormat' '')".Trim()
    if ("$(Get-ObjectProperty $item 'CollectionHint' '')" -eq '3D' -and (-not $threeDFormat -or $threeDFormat -eq 'Unknown 3D')) { $issues += 'Unverified3DLayout' }
    $issues = @($issues | Select-Object -Unique)
    $requiresReview = [bool](@($issues).Count -gt 0)
    $reconciled = [pscustomobject]@{
        InventoryId = $inventoryId
        OriginalPath = $originalPath
        OriginalTitle = Get-ObjectProperty $item 'OriginalTitle'
        OriginalYear = Get-ObjectProperty $item 'OriginalYear'
        Collection = Get-ObjectProperty $item 'Collection'
        CollectionHint = Get-ObjectProperty $item 'CollectionHint'
        ResolutionClass = Get-ObjectProperty $item 'ResolutionClass'
        ThreeDFormat = Get-ObjectProperty $item 'ThreeDFormat'
        OriginalEdition = Get-ObjectProperty $item 'OriginalEdition'
        IdentificationSource = $identificationSource
        ReconciledTmdbMovieId = $resolvedId
        CanonicalTitle = $canonicalTitle
        CanonicalReleaseYear = $canonicalYear
        PreviousTmdbMovieId = $previousId
        PreviousMatchStatus = Get-ObjectProperty $item 'MatchStatus'
        PlexPathMatchCount = $pathMatchCount
        PlexRatingKey = $plexRatingKey
        PlexLibrary = $plexLibrary
        PlexTitle = $plexTitle
        PlexYear = $plexYear
        PlexOriginalFilePath = $plexPath
        PlexGuidValues = $plexGuidValues
        PlexTmdbIds = $plexTmdbIds
        PlexImdbIds = $plexImdbIds
        RequiresManualReview = $requiresReview
        ReviewIssues = $issues
        OriginalEnrichedItem = $item
    }
    $reconciledItems += $reconciled
    if ($requiresReview) {
        $reviewRows += [pscustomobject]@{
            InventoryId = $inventoryId; OriginalPath = $originalPath; IdentificationSource = $identificationSource; ReconciledTmdbMovieId = $resolvedId
            PlexRatingKey = $plexRatingKey; PlexLibrary = $plexLibrary; PlexOriginalFilePath = $plexPath; PlexTmdbIds = ($plexTmdbIds -join ';'); PlexImdbIds = ($plexImdbIds -join ';'); Issues = ($issues -join ';')
        }
    }
}
Write-Progress -Activity 'Reconciling Plex metadata' -Completed

$inventoryPathKeys = @($inventoryItemsByPath.Keys)
foreach ($part in $allPlexParts) {
    if ($inventoryPathKeys -notcontains $part.InventoryPathKey) {
        $reviewRows += [pscustomobject]@{
            InventoryId = ''; OriginalPath = ''; IdentificationSource = ''; ReconciledTmdbMovieId = ''; PlexRatingKey = $part.Movie.RatingKey; PlexLibrary = $part.Movie.LibraryTitle
            PlexOriginalFilePath = $part.PlexPath; PlexTmdbIds = (@($part.Movie.TmdbIds) -join ';'); PlexImdbIds = (@($part.Movie.ImdbIds) -join ';'); Issues = 'PlexPartNotInInventory'
        }
    }
}

$resolvedItems = @($reconciledItems | Where-Object { $null -ne $_.ReconciledTmdbMovieId })
$groups = @($resolvedItems | Group-Object ReconciledTmdbMovieId | Where-Object Count -gt 1)
$groupRows = @()
foreach ($group in $groups) {
    foreach ($item in $group.Group) {
        $variant = if ($item.CollectionHint -eq '3D') { '3D' } else { $item.ResolutionClass }
        $groupRows += [pscustomobject]@{
            GroupId = "tmdb-$($group.Name)"; TmdbMovieId = $item.ReconciledTmdbMovieId; CanonicalTitle = $item.CanonicalTitle; CanonicalReleaseYear = $item.CanonicalReleaseYear
            InventoryId = $item.InventoryId; IdentificationSource = $item.IdentificationSource; Collection = $item.Collection; Variant = $variant; ThreeDFormat = $item.ThreeDFormat
            ExistingEdition = $item.OriginalEdition; OriginalPath = $item.OriginalPath
        }
    }
}

$generatedAt = (Get-Date).ToUniversalTime().ToString('o')
$document = [ordered]@{
    SchemaVersion = 1
    GeneratedAtUtc = $generatedAt
    Tool = 'New-PlexReconciledInventory.ps1'
    SourceEnrichedInventory = $resolvedInventoryPath
    SourceEnrichedInventorySha256 = (Get-FileHash -LiteralPath $resolvedInventoryPath -Algorithm SHA256).Hash
    PlexBaseUrl = $plexBaseUrl
    ReadOnly = $true
    ItemCount = @($reconciledItems).Count
    PlexTmdbCount = @($reconciledItems | Where-Object IdentificationSource -eq 'PlexTMDB').Count
    PlexImdbCount = @($reconciledItems | Where-Object IdentificationSource -eq 'PlexIMDb').Count
    TmdbEnrichmentCount = @($reconciledItems | Where-Object IdentificationSource -eq 'TMDBEnrichment').Count
    UnresolvedCount = @($reconciledItems | Where-Object IdentificationSource -eq 'Unresolved').Count
    ManualReviewItemCount = @($reconciledItems | Where-Object RequiresManualReview).Count
    ExceptionRowCount = @($reviewRows).Count
    CrossVersionGroupCount = @($groups).Count
    PlexMovieLibraryCount = @($movieSections).Count
    PlexMovieRecordCount = @($plexMovies).Count
    PlexMediaPartCount = @($allPlexParts).Count
    InventoryFilesMatchedToPlex = @($reconciledItems | Where-Object PlexPathMatchCount -eq 1).Count
    LibraryDiagnostics = $libraryDiagnostics
    Items = $reconciledItems
}

$jsonPath = Join-Path $runDirectory 'plex-reconciled-inventory.json'
$csvPath = Join-Path $runDirectory 'plex-reconciled-inventory.csv'
$summaryPath = Join-Path $runDirectory 'plex-reconciliation-summary.md'
$reviewPath = Join-Path $runDirectory 'plex-reconciliation-review.csv'
$groupsPath = Join-Path $runDirectory 'plex-cross-version-groups.csv'
$document | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$csvRows = @($reconciledItems | ForEach-Object {
    [pscustomobject]@{
        InventoryId = $_.InventoryId; OriginalPath = $_.OriginalPath; OriginalTitle = $_.OriginalTitle; OriginalYear = $_.OriginalYear; Collection = $_.Collection
        ResolutionClass = $_.ResolutionClass; ThreeDFormat = $_.ThreeDFormat; ExistingEdition = $_.OriginalEdition; IdentificationSource = $_.IdentificationSource
        ReconciledTmdbMovieId = $_.ReconciledTmdbMovieId; CanonicalTitle = $_.CanonicalTitle; CanonicalReleaseYear = $_.CanonicalReleaseYear; PreviousTmdbMovieId = $_.PreviousTmdbMovieId
        PlexRatingKey = $_.PlexRatingKey; PlexLibrary = $_.PlexLibrary; PlexTitle = $_.PlexTitle; PlexYear = $_.PlexYear; PlexOriginalFilePath = $_.PlexOriginalFilePath
        PlexGuidValues = ($_.PlexGuidValues -join ';'); PlexTmdbIds = ($_.PlexTmdbIds -join ';'); PlexImdbIds = ($_.PlexImdbIds -join ';')
        RequiresManualReview = $_.RequiresManualReview; ReviewIssues = ($_.ReviewIssues -join ';')
    }
})
if (@($csvRows).Count -gt 0) { $csvRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 }
else { '"InventoryId","OriginalPath","OriginalTitle","OriginalYear","Collection","ResolutionClass","ThreeDFormat","ExistingEdition","IdentificationSource","ReconciledTmdbMovieId","CanonicalTitle","CanonicalReleaseYear","PreviousTmdbMovieId","PlexRatingKey","PlexLibrary","PlexTitle","PlexYear","PlexOriginalFilePath","PlexGuidValues","PlexTmdbIds","PlexImdbIds","RequiresManualReview","ReviewIssues"' | Set-Content -LiteralPath $csvPath -Encoding UTF8 }

if (@($reviewRows).Count -gt 0) { $reviewRows | Export-Csv -LiteralPath $reviewPath -NoTypeInformation -Encoding UTF8 }
else { '"InventoryId","OriginalPath","IdentificationSource","ReconciledTmdbMovieId","PlexRatingKey","PlexLibrary","PlexOriginalFilePath","PlexTmdbIds","PlexImdbIds","Issues"' | Set-Content -LiteralPath $reviewPath -Encoding UTF8 }
if (@($groupRows).Count -gt 0) { $groupRows | Export-Csv -LiteralPath $groupsPath -NoTypeInformation -Encoding UTF8 }
else { '"GroupId","TmdbMovieId","CanonicalTitle","CanonicalReleaseYear","InventoryId","IdentificationSource","Collection","Variant","ThreeDFormat","ExistingEdition","OriginalPath"' | Set-Content -LiteralPath $groupsPath -Encoding UTF8 }

$summary = [System.Collections.Generic.List[string]]::new()
$summary.Add('# Plex metadata reconciliation summary')
$summary.Add('')
$summary.Add("Generated: $generatedAt")
$summary.Add('')
$summary.Add("- Inventory items: $($document.ItemCount)")
$summary.Add("- Plex movie libraries discovered: $($document.PlexMovieLibraryCount)")
$summary.Add("- Plex movie records read: $($document.PlexMovieRecordCount)")
$summary.Add("- Plex media parts read: $($document.PlexMediaPartCount)")
$summary.Add("- Inventory files path-matched to Plex: $($document.InventoryFilesMatchedToPlex)")
$summary.Add("- Resolved from Plex TMDB IDs: $($document.PlexTmdbCount)")
$summary.Add("- Resolved from Plex IMDb IDs through TMDB: $($document.PlexImdbCount)")
$summary.Add("- Retained from filename-based TMDB enrichment: $($document.TmdbEnrichmentCount)")
$summary.Add("- Unresolved: $($document.UnresolvedCount)")
$summary.Add("- Inventory items requiring attention: $($document.ManualReviewItemCount)")
$summary.Add("- Total exception rows, including unmatched Plex parts: $($document.ExceptionRowCount)")
$summary.Add("- Cross-version TMDB groups: $($document.CrossVersionGroupCount)")
$summary.Add('')
$summary.Add('Plex identification was accepted only when a Plex rating key linked uniquely to an inventory file by normalized path. Titles were not used for identity. Existing collection, resolution and 3D classifications were preserved.')
$summary.Add('')
$summary.Add('## Library enumeration')
$summary.Add('')
$summary.Add('| Section | Library | Plex reported | Records retrieved | Media parts | Paths matched to inventory |')
$summary.Add('| --- | --- | ---: | ---: | ---: | ---: |')
foreach ($diagnostic in $libraryDiagnostics) {
    $reported = if ($null -eq $diagnostic.PlexReportedRecords) { 'Unknown' } else { "$($diagnostic.PlexReportedRecords)" }
    $summary.Add("| $(Escape-Markdown $diagnostic.SectionKey) | $(Escape-Markdown $diagnostic.LibraryTitle) | $reported | $($diagnostic.RecordsRetrieved) | $($diagnostic.MediaPartsRetrieved) | $($diagnostic.PathsMatchedToInventory) |")
}
$issueCounts = @($reviewRows | ForEach-Object { @($_.Issues -split ';' | Where-Object { $_ }) } | Group-Object | Sort-Object Count -Descending)
if (@($issueCounts).Count -gt 0) {
    $summary.Add('')
    $summary.Add('## Exception counts')
    $summary.Add('')
    $summary.Add('| Exception | Count |')
    $summary.Add('| --- | ---: |')
    foreach ($issue in $issueCounts) { $summary.Add("| $(Escape-Markdown $issue.Name) | $($issue.Count) |") }
}
$summary | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "Plex reconciliation complete: $runDirectory"
Write-Host 'Only Plex GET requests were used. No media or service configuration was modified.'
[pscustomobject]@{
    OutputDirectory = $runDirectory; ReconciledJson = $jsonPath; ReconciledCsv = $csvPath; SummaryMarkdown = $summaryPath
    ReviewCsv = $reviewPath; CrossVersionGroupsCsv = $groupsPath; ItemCount = @($reconciledItems).Count
}

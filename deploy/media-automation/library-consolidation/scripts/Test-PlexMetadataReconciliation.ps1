[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    Write-Host "PASS  $Message"
}

function New-EnrichedItem {
    param(
        [string]$Id, [string]$Path, [string]$Collection, [string]$Hint, [string]$Resolution,
        [AllowNull()][object]$TmdbId, [string]$MatchStatus, [AllowNull()][string]$ThreeDFormat
    )
    return [pscustomobject]@{
        InventoryId = $Id; OriginalPath = $Path; OriginalTitle = [System.IO.Path]::GetFileNameWithoutExtension($Path); OriginalYear = $null
        OriginalEdition = $null; Collection = $Collection; CollectionHint = $Hint; ResolutionClass = $Resolution; ThreeDFormat = $ThreeDFormat
        MatchStatus = $MatchStatus; ConfirmedTmdbMovieId = $TmdbId; CanonicalTitle = if ($null -ne $TmdbId) { "Previous $Id" } else { $null }
        CanonicalReleaseYear = if ($null -ne $TmdbId) { 2000 } else { $null }
        OriginalInventoryItem = [pscustomobject]@{ RootPath = "D:\Media Centre"; FullPath = $Path }
    }
}

function New-PlexMovie {
    param([string]$RatingKey, [string]$Title, [int]$Year, [string[]]$Guids, [string[]]$Paths)
    return [pscustomobject]@{
        ratingKey = $RatingKey; title = $Title; year = $Year
        Guid = @($Guids | ForEach-Object { [pscustomobject]@{ id = $_ } })
        Media = @([pscustomobject]@{ Part = @($Paths | ForEach-Object { [pscustomobject]@{ file = $_ } }) })
    }
}

$scriptPath = Join-Path $PSScriptRoot "New-PlexReconciledInventory.ps1"
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("case-plex-reconciliation-{0}" -f [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $inventoryPath = Join-Path $fixtureRoot "enriched-media-inventory.json"
    $configPath = Join-Path $fixtureRoot "plex-reconciliation.config.json"
    $plexFixturePath = Join-Path $fixtureRoot "plex-fixture.json"
    $incompletePlexFixturePath = Join-Path $fixtureRoot "plex-fixture-incomplete.json"
    $tmdbFixturePath = Join-Path $fixtureRoot "tmdb-fixture.json"
    $outputRoot = Join-Path $fixtureRoot "reports"
    $cacheRoot = Join-Path $fixtureRoot "tmdb-cache"

    $items = @(
        (New-EnrichedItem "plex-tmdb" "D:\Media Centre\Movies\Ambiguous.mkv" "Movies" "1080p" "1080p" $null "Ambiguous" $null),
        (New-EnrichedItem "plex-imdb" "D:\Media Centre\Movies\IMDb Only.mkv" "Movies" "1080p" "1080p" $null "Unmatched" $null),
        (New-EnrichedItem "fallback" "D:\Media Centre\Movies\Fallback.mkv" "Movies" "1080p" "1080p" 303 "HighConfidence" $null),
        (New-EnrichedItem "missing-ids" "D:\Media Centre\Movies\Missing IDs.mkv" "Movies" "1080p" "1080p" 404 "HighConfidence" $null),
        (New-EnrichedItem "conflict" "D:\Media Centre\Movies\Conflict.mkv" "Movies" "1080p" "1080p" 505 "HighConfidence" $null),
        (New-EnrichedItem "duplicate" "D:\Media Centre\Movies\Duplicate Map.mkv" "Movies" "1080p" "1080p" 707 "HighConfidence" $null),
        (New-EnrichedItem "unresolved" "D:\Media Centre\Movies\Unresolved.mkv" "Movies" "1080p" "1080p" $null "Ambiguous" $null),
        (New-EnrichedItem "plex-3d" "D:\Media Centre\3D\Ambiguous 3D.mkv" "3D Movies" "3D" "1080p" $null "Ambiguous" "Unknown 3D")
    )
    [ordered]@{ SchemaVersion = 1; ItemCount = @($items).Count; Items = $items } |
        ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $inventoryPath -Encoding UTF8

    [ordered]@{
        plexBaseUrl = "http://127.0.0.1:32400"
        pageSize = 2
        outputDirectory = $outputRoot
        cacheDirectory = $cacheRoot
        pathMappings = @(
            [ordered]@{ plexPrefix = "/plex/movies"; inventoryPrefix = "D:\Media Centre\Movies" },
            [ordered]@{ plexPrefix = "/plex/three-d"; inventoryPrefix = "D:\Media Centre\3D" }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8

    $imdbListRecord = New-PlexMovie "2" "IMDb Only" 2002 @("plex://movie/local-imdb-only") @("/plex/movies/IMDb Only.mkv")
    $plexMovies = @(
        (New-PlexMovie "1" "Ambiguous Corrected" 2001 @("tmdb://101") @("/plex/movies/temporary/../Ambiguous.mkv", "/plex/movies/Ambiguous.mkv")),
        $imdbListRecord,
        (New-PlexMovie "3" "Missing IDs" 2004 @() @("/plex/movies/Missing IDs.mkv")),
        (New-PlexMovie "4" "Conflict Corrected" 2006 @("tmdb://606") @("/plex/movies/Conflict.mkv")),
        (New-PlexMovie "5" "Duplicate One" 2007 @("tmdb://701") @("/plex/movies/Duplicate Map.mkv")),
        (New-PlexMovie "6" "Duplicate Two" 2007 @("tmdb://702") @("/plex/movies/Duplicate Map.mkv")),
        (New-PlexMovie "7" "Ambiguous Corrected" 2001 @("tmdb://101") @("/plex/three-d/Ambiguous 3D.mkv")),
        (New-PlexMovie "8" "Unresolved" 2008 @("tmdb://808") @("/plex/movies/Wrong Location.mkv"))
    )
    $imdbDetail = New-PlexMovie "2" "IMDb Only" 2002 @("imdb://tt0000202") @("/plex/movies/IMDb Only.mkv")
    $plexFixture = [ordered]@{
        sections = @(
            [ordered]@{ key = "7"; type = "movie"; title = "Movies" },
            [ordered]@{ key = "8"; type = "movie"; title = "Movies 4K" },
            [ordered]@{ key = "9"; type = "movie"; title = "Movies 3D" },
            [ordered]@{ key = "10"; type = "show"; title = "TV Shows" }
        )
        sectionItems = [ordered]@{
            "7" = @($plexMovies[0..5])
            "8" = @($plexMovies[7])
            "9" = @($plexMovies[6])
            "10" = @((New-PlexMovie "tv-1" "Not a movie" 2020 @() @("/plex/tv/show.mkv")))
        }
        scalarSingleItemResponses = $true
        details = [ordered]@{ "2" = $imdbDetail }
    }
    $plexFixture | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $plexFixturePath -Encoding UTF8
    $incompleteFixture = $plexFixture | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $incompleteFixture | Add-Member -NotePropertyName sectionReportedTotals -NotePropertyValue ([pscustomobject]@{ "7" = 7; "8" = 1; "9" = 1 })
    $incompleteFixture | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $incompletePlexFixturePath -Encoding UTF8
    [ordered]@{
        find = [ordered]@{
            "tt0000202" = [ordered]@{ movie_results = @([ordered]@{ id = 202; title = "IMDb Resolved"; release_date = "2002-02-02" }) }
        }
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tmdbFixturePath -Encoding UTF8

    $inventoryHash = (Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash
    [Environment]::SetEnvironmentVariable("CASE_TEST_MISSING_PLEX_TOKEN", $null)
    $missingCredentialFailed = $false
    try {
        & $scriptPath -EnrichedInventoryPath $inventoryPath -ConfigPath $configPath -PlexTokenEnvironmentVariable "CASE_TEST_MISSING_PLEX_TOKEN" | Out-Null
    }
    catch { $missingCredentialFailed = [bool]($_.Exception.Message -match 'Plex token is missing') }
    Assert-True -Condition $missingCredentialFailed -Message "missing Plex credentials fail before any network call"

    $secret = "fixture-token-must-not-be-persisted"
    [Environment]::SetEnvironmentVariable("CASE_TEST_PLEX_TOKEN", $secret)
    $enumeration = & $scriptPath -ConfigPath $configPath -PlexTokenEnvironmentVariable "CASE_TEST_PLEX_TOKEN" -PlexFixturePath $plexFixturePath -PlexEnumerationOnly
    Assert-True -Condition ($enumeration.Mode -eq 'PlexEnumerationOnly' -and $enumeration.MovieLibraryCount -eq 3 -and $enumeration.PlexMovieRecordCount -eq 8) -Message "enumeration-only mode needs no inventory and returns every movie record"
    Assert-True -Condition (-not (Test-Path -LiteralPath $outputRoot)) -Message "enumeration-only mode produces no reconciliation reports"
    $result = & $scriptPath -EnrichedInventoryPath $inventoryPath -ConfigPath $configPath -PlexTokenEnvironmentVariable "CASE_TEST_PLEX_TOKEN" -PlexFixturePath $plexFixturePath -TmdbFixturePath $tmdbFixturePath
    foreach ($path in @($result.ReconciledJson, $result.ReconciledCsv, $result.SummaryMarkdown, $result.ReviewCsv, $result.CrossVersionGroupsCsv)) {
        Assert-True -Condition (Test-Path -LiteralPath $path) -Message "required output exists: $([System.IO.Path]::GetFileName($path))"
    }

    $documentText = Get-Content -LiteralPath $result.ReconciledJson -Raw
    $document = $documentText | ConvertFrom-Json
    Assert-True -Condition ($documentText -notmatch [regex]::Escape($secret)) -Message "Plex token is not persisted in output"
    Assert-True -Condition ($document.PlexTmdbCount -eq 3 -and $document.PlexImdbCount -eq 1) -Message "Plex TMDB and IMDb matches are counted"
    Assert-True -Condition ($document.PlexMovieLibraryCount -eq 3 -and $document.PlexMovieRecordCount -eq 8) -Message "all movie libraries and every paginated record are accumulated"
    Assert-True -Condition ($document.PlexMediaPartCount -eq 9) -Message "multiple media parts on one movie are counted"
    $libraryDiagnostics = @($document.LibraryDiagnostics)
    Assert-True -Condition ($libraryDiagnostics.Count -eq 3) -Message "per-library diagnostics cover all movie sections"
    $standardDiagnostic = @($libraryDiagnostics | Where-Object SectionKey -eq '7')[0]
    Assert-True -Condition ($standardDiagnostic.PlexReportedRecords -eq 6 -and $standardDiagnostic.RecordsRetrieved -eq 6 -and $standardDiagnostic.MediaPartsRetrieved -eq 7 -and $standardDiagnostic.PathsMatchedToInventory -eq 5) -Message "multi-page library diagnostics report records, parts and path matches"
    $fourKDiagnostic = @($libraryDiagnostics | Where-Object SectionKey -eq '8')[0]
    Assert-True -Condition ($fourKDiagnostic.PlexReportedRecords -eq 1 -and $fourKDiagnostic.RecordsRetrieved -eq 1) -Message "single-item Plex responses remain enumerable under StrictMode"

    $plexTmdb = $document.Items | Where-Object InventoryId -eq "plex-tmdb"
    $plexImdb = $document.Items | Where-Object InventoryId -eq "plex-imdb"
    $fallback = $document.Items | Where-Object InventoryId -eq "fallback"
    $missingIds = $document.Items | Where-Object InventoryId -eq "missing-ids"
    $conflict = $document.Items | Where-Object InventoryId -eq "conflict"
    $duplicate = $document.Items | Where-Object InventoryId -eq "duplicate"
    $unresolved = $document.Items | Where-Object InventoryId -eq "unresolved"
    $threeD = $document.Items | Where-Object InventoryId -eq "plex-3d"

    Assert-True -Condition ($plexTmdb.IdentificationSource -eq 'PlexTMDB' -and $plexTmdb.ReconciledTmdbMovieId -eq 101) -Message "path-linked Plex TMDB ID replaces an ambiguous filename match"
    Assert-True -Condition ($plexTmdb.PlexOriginalFilePath -eq '/plex/movies/temporary/../Ambiguous.mkv') -Message "container-to-Windows mapping normalizes identity while preserving the original Plex path"
    Assert-True -Condition ($plexImdb.IdentificationSource -eq 'PlexIMDb' -and $plexImdb.ReconciledTmdbMovieId -eq 202) -Message "item detail lookup and IMDb-to-TMDB resolution work"
    Assert-True -Condition ($fallback.IdentificationSource -eq 'TMDBEnrichment' -and $fallback.ReconciledTmdbMovieId -eq 303) -Message "existing TMDB enrichment remains the fallback"
    Assert-True -Condition ($missingIds.IdentificationSource -eq 'TMDBEnrichment' -and $missingIds.ReviewIssues -contains 'MissingPlexExternalIds') -Message "missing Plex external IDs are flagged without discarding the fallback"
    Assert-True -Condition ($conflict.IdentificationSource -eq 'PlexTMDB' -and $conflict.ReconciledTmdbMovieId -eq 606 -and $conflict.ReviewIssues -contains 'PlexTmdbConflict') -Message "unique Plex matches win while conflicts remain visible"
    Assert-True -Condition ($duplicate.IdentificationSource -eq 'TMDBEnrichment' -and $duplicate.ReviewIssues -contains 'DuplicatePlexFileMappings') -Message "duplicate Plex path mappings cannot override the prior match"
    Assert-True -Condition ($unresolved.IdentificationSource -eq 'Unresolved' -and $unresolved.RequiresManualReview) -Message "matching Plex titles cannot bypass file-path identity"
    Assert-True -Condition ($threeD.CollectionHint -eq '3D' -and $threeD.ThreeDFormat -eq 'Unknown 3D' -and $null -eq $threeD.OriginalEdition) -Message "3D classification is preserved without inventing an edition"
    Assert-True -Condition ($threeD.ReviewIssues -contains 'Unverified3DLayout') -Message "uncertain 3D layout remains a meaningful exception"

    $review = @(Import-Csv -LiteralPath $result.ReviewCsv)
    Assert-True -Condition (@($review | Where-Object Issues -eq 'PlexPartNotInInventory').Count -eq 1) -Message "Plex parts absent from the inventory are reported"
    $groups = @(Import-Csv -LiteralPath $result.CrossVersionGroupsCsv)
    $group101 = @($groups | Where-Object TmdbMovieId -eq '101')
    Assert-True -Condition (@($group101).Count -eq 2) -Message "reconciled TMDB IDs drive cross-version grouping"
    Assert-True -Condition (@($group101.Variant | Sort-Object -Unique).Count -eq 2) -Message "1080p and 3D remain distinct variants without edition assumptions"
    Assert-True -Condition ((Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash -eq $inventoryHash) -Message "source enriched inventory remains unchanged"

    $incompleteEnumerationFailed = $false
    try {
        & $scriptPath -EnrichedInventoryPath $inventoryPath -ConfigPath $configPath -PlexTokenEnvironmentVariable "CASE_TEST_PLEX_TOKEN" -PlexFixturePath $incompletePlexFixturePath -TmdbFixturePath $tmdbFixturePath | Out-Null
    }
    catch { $incompleteEnumerationFailed = [bool]($_.Exception.Message -match "Incomplete Plex enumeration.*reported 7 records.*empty page") }
    Assert-True -Condition $incompleteEnumerationFailed -Message "an incomplete Plex library fails clearly instead of producing a partial report"

    Write-Host "Plex metadata reconciliation fixture checks passed."
}
finally {
    [Environment]::SetEnvironmentVariable("CASE_TEST_PLEX_TOKEN", $null)
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}

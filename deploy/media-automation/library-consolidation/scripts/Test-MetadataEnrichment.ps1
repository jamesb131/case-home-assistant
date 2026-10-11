[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    Write-Host "PASS  $Message"
}

function New-InventoryItem {
    param([string]$Id, [string]$Title, [AllowNull()][object]$Year, [string]$Path, [string]$Collection, [string]$Hint, [string]$Resolution, [AllowNull()][string]$ThreeDFormat, [AllowNull()][string]$Edition)
    return [ordered]@{
        Id = $Id; Title = $Title; Year = $Year; FullPath = $Path; FileName = [System.IO.Path]::GetFileName($Path)
        Collection = $Collection; CollectionHint = $Hint; ResolutionClass = $Resolution; ThreeDFormat = $ThreeDFormat; Edition = $Edition
        Sha256 = $null; ConfirmedDuplicateGroup = $null
    }
}

$scriptPath = Join-Path $PSScriptRoot "New-EnrichedMediaInventory.ps1"
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("case-metadata-enrichment-{0}" -f [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $inventoryPath = Join-Path $fixtureRoot "media-inventory.json"
    $fixturePath = Join-Path $fixtureRoot "tmdb-fixture.json"
    $outputRoot = Join-Path $fixtureRoot "output"
    $mediaRoot = Join-Path $fixtureRoot "read-only-media"
    $items = @(
        (New-InventoryItem "thing" "The Thing" $null (Join-Path $mediaRoot "The Thing.mkv") "Standard" "1080p" "1080p" $null $null),
        (New-InventoryItem "sequel" "Toy Story II" 1999 (Join-Path $mediaRoot "Toy Story II (1999).mkv") "Standard" "1080p" "1080p" $null $null),
        (New-InventoryItem "conflict" "Dune" 1984 (Join-Path $mediaRoot "Dune (1984).mkv") "Standard" "1080p" "1080p" $null $null),
        (New-InventoryItem "matrix-hd" "The Matrix" 1999 (Join-Path $mediaRoot "The Matrix.mkv") "Standard" "1080p" "1080p" $null $null),
        (New-InventoryItem "matrix-uhd" "Matrix, The" 1999 (Join-Path $mediaRoot "The Matrix 2160p.mkv") "4K" "2160p" "2160p" $null $null),
        (New-InventoryItem "matrix-3d" "The Matrix" 1999 (Join-Path $mediaRoot "The Matrix HSBS.mkv") "3D" "3D" "1080p" "Side-by-side" $null),
        (New-InventoryItem "wall-e" "001 - WALL-E 1080p" 2008 (Join-Path $mediaRoot "001 - WALL-E 1080p.mkv") "Standard" "1080p" "1080p" $null $null),
        (New-InventoryItem "avatar-3d" "Avatar 3D" 2009 (Join-Path $mediaRoot "Avatar 3D.mkv") "3D" "3D" "1080p" "Unknown 3D" "Extended Cut")
    )
    $inventory = [ordered]@{
        SchemaVersion = 1
        Roots = @([ordered]@{ Name = "Fixture"; Path = $mediaRoot; ClassificationHint = "1080p" })
        ItemCount = @($items).Count
        Items = $items
    }
    $inventory | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $inventoryPath -Encoding UTF8

    $fixture = [ordered]@{
        searches = [ordered]@{
            "the thing" = [ordered]@{ results = @(
                [ordered]@{ id = 1091; title = "The Thing"; original_title = "The Thing"; release_date = "1982-06-25"; popularity = 40 },
                [ordered]@{ id = 60935; title = "The Thing"; original_title = "The Thing"; release_date = "2011-10-12"; popularity = 25 }
            ) }
            "toy story 2" = [ordered]@{ results = @([ordered]@{ id = 863; title = "Toy Story 2"; original_title = "Toy Story 2"; release_date = "1999-10-30"; popularity = 50 }) }
            "dune" = [ordered]@{ results = @([ordered]@{ id = 438631; title = "Dune"; original_title = "Dune"; release_date = "2021-09-15"; popularity = 80 }) }
            "the matrix" = [ordered]@{ results = @([ordered]@{ id = 603; title = "The Matrix"; original_title = "The Matrix"; release_date = "1999-03-30"; popularity = 90 }) }
            "wall e" = [ordered]@{ results = @([ordered]@{ id = 10681; title = "WALL-E"; original_title = "WALL-E"; release_date = "2008-06-22"; popularity = 70 }) }
            "avatar" = [ordered]@{ results = @([ordered]@{ id = 19995; title = "Avatar"; original_title = "Avatar"; release_date = "2009-12-15"; popularity = 100 }) }
        }
        movies = [ordered]@{
            "1091" = [ordered]@{ id = 1091; title = "The Thing"; release_date = "1982-06-25" }
        }
    }
    $fixture | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixturePath -Encoding UTF8
    $beforeHash = (Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash

    $missingCredentialFailed = $false
    [Environment]::SetEnvironmentVariable("CASE_TEST_MISSING_TMDB_TOKEN", $null)
    try {
        & $scriptPath -InventoryPath $inventoryPath -OutputDirectory (Join-Path $outputRoot "missing") -TokenEnvironmentVariable "CASE_TEST_MISSING_TMDB_TOKEN" | Out-Null
    }
    catch {
        $missingCredentialFailed = [bool]($_.Exception.Message -match "TMDB API read token is missing")
    }
    Assert-True -Condition $missingCredentialFailed -Message "missing TMDB credentials fail with a clear error"

    $result = & $scriptPath -InventoryPath $inventoryPath -OutputDirectory (Join-Path $outputRoot "fixture") -CacheDirectory (Join-Path $outputRoot "cache") -TmdbFixturePath $fixturePath
    foreach ($path in @($result.EnrichedJson, $result.EnrichedCsv, $result.SummaryMarkdown, $result.ManualReviewCsv, $result.ManualReviewMarkdown, $result.CrossVersionGroupsCsv, $result.OverrideTemplateCsv)) {
        Assert-True -Condition (Test-Path -LiteralPath $path) -Message "required output exists: $([System.IO.Path]::GetFileName($path))"
    }
    $enriched = Get-Content -LiteralPath $result.EnrichedJson -Raw | ConvertFrom-Json
    $thing = $enriched.Items | Where-Object InventoryId -eq "thing"
    $sequel = $enriched.Items | Where-Object InventoryId -eq "sequel"
    $conflict = $enriched.Items | Where-Object InventoryId -eq "conflict"
    $wallE = $enriched.Items | Where-Object InventoryId -eq "wall-e"
    $avatar = $enriched.Items | Where-Object InventoryId -eq "avatar-3d"
    Assert-True -Condition ($thing.MatchStatus -eq "Ambiguous" -and $null -eq $thing.ConfirmedTmdbMovieId) -Message "same-title remakes remain ambiguous"
    Assert-True -Condition (@($thing.AlternativeCandidates).Count -eq 2) -Message "ambiguous remakes include alternatives"
    Assert-True -Condition ($sequel.MatchStatus -eq "HighConfidence" -and $sequel.ConfirmedTmdbMovieId -eq 863) -Message "Roman sequel numbering matches Arabic TMDB numbering"
    Assert-True -Condition ($conflict.MatchStatus -eq "Ambiguous" -and $null -eq $conflict.ConfirmedTmdbMovieId) -Message "conflicting years cannot auto-confirm"
    Assert-True -Condition ($wallE.MatchStatus -eq "HighConfidence" -and $wallE.ConfirmedTmdbMovieId -eq 10681) -Message "numeric prefixes, quality tags and punctuation variations normalize safely"
    Assert-True -Condition ($avatar.MatchStatus -eq "HighConfidence" -and $avatar.OriginalEdition -eq "Extended Cut") -Message "3D metadata match preserves the existing cut"
    Assert-True -Condition ($avatar.RequiresManualReview -and $avatar.ThreeDFormat -eq "Unknown 3D") -Message "uncertain 3D layout remains in manual review"

    $groups = @(Import-Csv -LiteralPath $result.CrossVersionGroupsCsv)
    $matrixRows = @($groups | Where-Object TmdbMovieId -eq "603")
    Assert-True -Condition (@($matrixRows).Count -eq 3) -Message "1080p, 4K and 3D copies group by confirmed TMDB ID"
    Assert-True -Condition (@($matrixRows.Variant | Sort-Object -Unique).Count -eq 3) -Message "cross-version group retains quality and 3D variants"
    Assert-True -Condition (-not ($matrixRows | Where-Object HashConfirmedDuplicate -eq "True")) -Message "different qualities are not declared byte-identical without hashes"

    $overridePath = Join-Path $fixtureRoot "metadata-overrides.csv"
    [pscustomobject]@{ InventoryId = "thing"; Decision = "Confirm"; TmdbMovieId = 1091; CanonicalTitle = "The Thing"; ReleaseYear = 1982; Notes = "Manually selected original" } |
        Export-Csv -LiteralPath $overridePath -NoTypeInformation -Encoding UTF8
    $overrideResult = & $scriptPath -InventoryPath $inventoryPath -OutputDirectory (Join-Path $outputRoot "override") -CacheDirectory (Join-Path $outputRoot "cache") -TmdbFixturePath $fixturePath -OverridesPath $overridePath
    $overrideInventory = Get-Content -LiteralPath $overrideResult.EnrichedJson -Raw | ConvertFrom-Json
    $overriddenThing = $overrideInventory.Items | Where-Object InventoryId -eq "thing"
    Assert-True -Condition ($overriddenThing.MatchStatus -eq "HighConfidence" -and $overriddenThing.MatchSource -eq "ManualOverride" -and $overriddenThing.ConfirmedTmdbMovieId -eq 1091) -Message "manual override confirms an ambiguous movie explicitly"
    Assert-True -Condition ((Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash -eq $beforeHash) -Message "source inventory remains unchanged"

    $emptyInventoryPath = Join-Path $fixtureRoot "empty-media-inventory.json"
    ([ordered]@{ SchemaVersion = 1; Roots = @([ordered]@{ Name = "Empty"; Path = (Join-Path $fixtureRoot "empty-media"); ClassificationHint = "1080p" }); ItemCount = 0; Items = @() } |
        ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $emptyInventoryPath -Encoding UTF8
    $emptyResult = & $scriptPath -InventoryPath $emptyInventoryPath -OutputDirectory (Join-Path $outputRoot "empty") -CacheDirectory (Join-Path $outputRoot "cache") -TmdbFixturePath $fixturePath
    $emptyDocument = Get-Content -LiteralPath $emptyResult.EnrichedJson -Raw | ConvertFrom-Json
    Assert-True -Condition ($emptyDocument.ItemCount -eq 0) -Message "empty inventories produce a valid zero-item enrichment"
    Assert-True -Condition ((Get-Content -LiteralPath $emptyResult.EnrichedCsv -TotalCount 1) -match 'InventoryId') -Message "empty inventories still produce a headed CSV"

    Write-Host "Metadata enrichment fixture checks passed."
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}

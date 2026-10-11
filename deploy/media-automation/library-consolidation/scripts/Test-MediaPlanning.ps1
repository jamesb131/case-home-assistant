[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
    Write-Host "PASS  $Message"
}

$inventoryScript = Join-Path $PSScriptRoot "New-MediaInventory.ps1"
$planScript = Join-Path $PSScriptRoot "New-MediaMigrationPlan.ps1"
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("case-media-planning-{0}" -f [guid]::NewGuid().ToString("N"))
$standardRoot = Join-Path $fixtureRoot "source-standard"
$uhdRoot = Join-Path $fixtureRoot "source-uhd"
$threeDRoot = Join-Path $fixtureRoot "source-3d"
$outputRoot = Join-Path $fixtureRoot "reports"
$targetRoot = Join-Path $fixtureRoot "target-movies"
$configPath = Join-Path $fixtureRoot "inventory.config.json"

try {
    foreach ($path in @($standardRoot, $uhdRoot, $threeDRoot, $outputRoot)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }

    $standardMovie = Join-Path $standardRoot "Example Movie (2024)"
    $uhdMovie = Join-Path $uhdRoot "Example Movie (2024)"
    $threeDMovie = Join-Path $threeDRoot "Depth Test (2012) 3D HSBS"
    foreach ($path in @($standardMovie, $uhdMovie, $threeDMovie)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }

    [System.IO.File]::WriteAllText((Join-Path $standardMovie "Example Movie (2024).mkv"), "same-sized-standard")
    [System.IO.File]::WriteAllText((Join-Path $uhdMovie "Example Movie (2024).mkv"), "same-sized-standard")
    [System.IO.File]::WriteAllText((Join-Path $standardMovie "Example Movie (2024).en.forced.srt"), "subtitle")
    [System.IO.File]::WriteAllText((Join-Path $threeDMovie "Depth Test (2012) 3D HSBS.mkv"), "3d-video")
    [System.IO.File]::WriteAllText((Join-Path $standardRoot "orphan.en.srt"), "orphan")

    $sourceFiles = @(Get-ChildItem -LiteralPath $standardRoot, $uhdRoot, $threeDRoot -File -Recurse)
    $before = @{}
    foreach ($file in $sourceFiles) {
        $before[$file.FullName] = [pscustomobject]@{
            Hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            Length = $file.Length
            LastWriteTimeUtc = $file.LastWriteTimeUtc
        }
    }

    $config = [ordered]@{
        roots = @(
            [ordered]@{ name = "Standard"; path = $standardRoot; classificationHint = "1080p" },
            [ordered]@{ name = "UHD"; path = $uhdRoot; classificationHint = "2160p" },
            [ordered]@{ name = "3D"; path = $threeDRoot; classificationHint = "3D" }
        )
        outputDirectory = $outputRoot
        target = [ordered]@{
            moviesRoot = $targetRoot
            qualityFolders = [ordered]@{ "1080p" = "1080p"; "2160p" = "2160p"; "3D" = "3D" }
        }
        videoExtensions = @(".mkv")
        subtitleExtensions = @(".srt")
        hashDuplicateCandidates = $true
    }
    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8

    $inventoryResult = & $inventoryScript -ConfigPath $configPath -SkipFfprobe
    Assert-True -Condition (Test-Path -LiteralPath $inventoryResult.InventoryJson) -Message "inventory JSON was created"
    Assert-True -Condition (Test-Path -LiteralPath $inventoryResult.InventoryCsv) -Message "inventory CSV was created"
    Assert-True -Condition (Test-Path -LiteralPath $inventoryResult.SummaryMarkdown) -Message "inventory summary was created"

    $inventory = Get-Content -LiteralPath $inventoryResult.InventoryJson -Raw | ConvertFrom-Json
    Assert-True -Condition ($inventory.ItemCount -eq 3) -Message "all fixture videos were inventoried"
    Assert-True -Condition ($inventory.UnassociatedSubtitleCount -eq 1) -Message "orphan subtitle was queued for review"
    Assert-True -Condition (@($inventory.Items | Where-Object ConfirmedDuplicateGroup).Count -eq 2) -Message "byte-identical candidate pair was hash-confirmed"
    Assert-True -Condition (@($inventory.Items | Where-Object { $_.ThreeDFormat -eq "SBS" }).Count -eq 1) -Message "3D side-by-side layout was identified"

    $planResult = & $planScript -InventoryPath $inventoryResult.InventoryJson -ConfigPath $configPath
    Assert-True -Condition (Test-Path -LiteralPath $planResult.PlanJson) -Message "migration plan JSON was created"
    $plan = Get-Content -LiteralPath $planResult.PlanJson -Raw | ConvertFrom-Json
    Assert-True -Condition ($plan.ItemCount -eq 3) -Message "all inventory items have plan entries"
    Assert-True -Condition (@($plan.Items | Where-Object { $_.DestinationVideoPath -match [regex]::Escape("{edition-3D SBS}") }).Count -eq 1) -Message "3D item uses a Plex edition tag"
    Assert-True -Condition (@($plan.Items | Where-Object { $_.SubtitlePlans.Count -eq 1 -and $_.SubtitlePlans[0].DestinationPath -match '\.en\.forced\.srt$' }).Count -eq 1) -Message "subtitle language and forced markers were preserved"

    $afterFiles = @(Get-ChildItem -LiteralPath $standardRoot, $uhdRoot, $threeDRoot -File -Recurse)
    Assert-True -Condition ($afterFiles.Count -eq $sourceFiles.Count) -Message "source file count is unchanged"
    foreach ($file in $afterFiles) {
        Assert-True -Condition ($before.ContainsKey($file.FullName)) -Message "source path remains present: $($file.Name)"
        Assert-True -Condition ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -eq $before[$file.FullName].Hash) -Message "source contents remain unchanged: $($file.Name)"
        Assert-True -Condition ($file.Length -eq $before[$file.FullName].Length) -Message "source length remains unchanged: $($file.Name)"
        Assert-True -Condition ($file.LastWriteTimeUtc -eq $before[$file.FullName].LastWriteTimeUtc) -Message "source timestamp remains unchanged: $($file.Name)"
    }

    Write-Host "Media planning fixture checks passed."
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

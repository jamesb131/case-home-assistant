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
    Assert-True -Condition (@($plan.Items | Where-Object { @($_.SubtitlePlans).Count -eq 1 -and $_.SubtitlePlans[0].DestinationPath -match '\.en\.forced\.srt$' }).Count -eq 1) -Message "subtitle language and forced markers were preserved"

    $afterFiles = @(Get-ChildItem -LiteralPath $standardRoot, $uhdRoot, $threeDRoot -File -Recurse)
    Assert-True -Condition (@($afterFiles).Count -eq @($sourceFiles).Count) -Message "source file count is unchanged"
    foreach ($file in $afterFiles) {
        Assert-True -Condition ($before.ContainsKey($file.FullName)) -Message "source path remains present: $($file.Name)"
        Assert-True -Condition ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -eq $before[$file.FullName].Hash) -Message "source contents remain unchanged: $($file.Name)"
        Assert-True -Condition ($file.Length -eq $before[$file.FullName].Length) -Message "source length remains unchanged: $($file.Name)"
        Assert-True -Condition ($file.LastWriteTimeUtc -eq $before[$file.FullName].LastWriteTimeUtc) -Message "source timestamp remains unchanged: $($file.Name)"
    }

    $cardinalityRoot = Join-Path $fixtureRoot "cardinality"
    $cardinalityStandard = Join-Path $cardinalityRoot "standard"
    $cardinalityUhd = Join-Path $cardinalityRoot "uhd"
    $cardinalityThreeD = Join-Path $cardinalityRoot "3d"
    $cardinalityConfigPath = Join-Path $cardinalityRoot "inventory.config.json"
    foreach ($path in @($cardinalityStandard, $cardinalityUhd, $cardinalityThreeD)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    $cardinalityConfig = [ordered]@{
        roots = @(
            [ordered]@{ name = "Standard"; path = $cardinalityStandard; classificationHint = "1080p" },
            [ordered]@{ name = "UHD"; path = $cardinalityUhd; classificationHint = "2160p" },
            [ordered]@{ name = "3D"; path = $cardinalityThreeD; classificationHint = "3D" }
        )
        outputDirectory = (Join-Path $cardinalityRoot "reports")
        target = [ordered]@{
            moviesRoot = (Join-Path $cardinalityRoot "target")
            qualityFolders = [ordered]@{ "1080p" = "1080p"; "2160p" = "2160p"; "3D" = "3D" }
        }
        videoExtensions = @(".mkv")
        subtitleExtensions = @(".srt")
        hashDuplicateCandidates = $false
    }
    $cardinalityConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cardinalityConfigPath -Encoding UTF8

    $zeroResult = & $inventoryScript -ConfigPath $cardinalityConfigPath -OutputDirectory (Join-Path $cardinalityRoot "reports-zero") -SkipFfprobe
    $zeroInventory = Get-Content -LiteralPath $zeroResult.InventoryJson -Raw | ConvertFrom-Json
    Assert-True -Condition ($zeroInventory.ItemCount -eq 0) -Message "zero-item inventory completes under StrictMode"
    Assert-True -Condition (Test-Path -LiteralPath $zeroResult.SummaryMarkdown) -Message "zero-item inventory writes its summary"
    $zeroSummary = Get-Content -LiteralPath $zeroResult.SummaryMarkdown -Raw
    Assert-True -Condition ($zeroSummary -match "Video files: 0") -Message "zero-item aggregate is reported as zero"
    $zeroPlanResult = & $planScript -InventoryPath $zeroResult.InventoryJson -ConfigPath $cardinalityConfigPath
    $zeroPlan = Get-Content -LiteralPath $zeroPlanResult.PlanJson -Raw | ConvertFrom-Json
    Assert-True -Condition ($zeroPlan.ItemCount -eq 0) -Message "zero-item migration plan completes under StrictMode"

    $singleFolder = Join-Path $cardinalityStandard "Only Movie (2020)"
    New-Item -ItemType Directory -Path $singleFolder -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $singleFolder "Only Movie (2020).mkv"), "single")
    [System.IO.File]::WriteAllText((Join-Path $singleFolder "Only Movie (2020).en.srt"), "subtitle")
    $singleResult = & $inventoryScript -ConfigPath $cardinalityConfigPath -OutputDirectory (Join-Path $cardinalityRoot "reports-one") -SkipFfprobe
    $singleInventory = Get-Content -LiteralPath $singleResult.InventoryJson -Raw | ConvertFrom-Json
    Assert-True -Condition ($singleInventory.ItemCount -eq 1) -Message "single-item inventory completes under StrictMode"
    $singlePlanResult = & $planScript -InventoryPath $singleResult.InventoryJson -ConfigPath $cardinalityConfigPath
    $singlePlan = Get-Content -LiteralPath $singlePlanResult.PlanJson -Raw | ConvertFrom-Json
    Assert-True -Condition ($singlePlan.ItemCount -eq 1) -Message "single-item migration plan completes under StrictMode"

    $secondFolder = Join-Path $cardinalityUhd "Second Movie (2021)"
    New-Item -ItemType Directory -Path $secondFolder -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $secondFolder "Second Movie (2021).mkv"), "second")
    $multipleResult = & $inventoryScript -ConfigPath $cardinalityConfigPath -OutputDirectory (Join-Path $cardinalityRoot "reports-multiple") -SkipFfprobe
    $multipleInventory = Get-Content -LiteralPath $multipleResult.InventoryJson -Raw | ConvertFrom-Json
    Assert-True -Condition ($multipleInventory.ItemCount -eq 2) -Message "multiple-item inventory completes under StrictMode"
    $multiplePlanResult = & $planScript -InventoryPath $multipleResult.InventoryJson -ConfigPath $cardinalityConfigPath
    $multiplePlan = Get-Content -LiteralPath $multiplePlanResult.PlanJson -Raw | ConvertFrom-Json
    Assert-True -Condition ($multiplePlan.ItemCount -eq 2) -Message "multiple-item migration plan completes under StrictMode"

    if ($env:OS -eq "Windows_NT") {
        $probeRoot = Join-Path $fixtureRoot "probe-behavior"
        $probeStandard = Join-Path $probeRoot "standard"
        $probeUhd = Join-Path $probeRoot "uhd"
        $probeThreeD = Join-Path $probeRoot "3d"
        $probeOutput = Join-Path $probeRoot "reports"
        foreach ($path in @($probeStandard, $probeUhd, $probeThreeD, $probeOutput)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
        $malformedFolder = Join-Path $probeStandard "Malformed Movie (2002)"
        $timeoutFolder = Join-Path $probeStandard "Timeout Movie (2003)"
        New-Item -ItemType Directory -Path $malformedFolder, $timeoutFolder -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $malformedFolder "Malformed Movie (2002).mp4"), "malformed")
        [System.IO.File]::WriteAllText((Join-Path $timeoutFolder "Timeout Movie (2003).mp4"), "timeout")

        $mockProbePath = Join-Path $probeRoot "mock-ffprobe.exe"
        $mockProbeSource = @'
using System;
using System.IO;
using System.Linq;
using System.Threading;

public static class MockFfprobe
{
    public static int Main(string[] args)
    {
        string mediaPath = args.Length == 0 ? string.Empty : args[args.Length - 1];
        if (mediaPath.IndexOf("Timeout Movie", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            Thread.Sleep(5000);
        }
        else
        {
            for (int index = 1; index <= 200; index++)
            {
                Console.Error.WriteLine("[h264] Invalid NAL unit size " + index);
            }
        }

        Console.Out.WriteLine("{\"streams\":[{\"codec_type\":\"video\",\"width\":1920,\"height\":1080,\"codec_name\":\"h264\"}],\"format\":{\"format_name\":\"mov,mp4\",\"duration\":\"1\"}}");
        return 0;
    }
}
'@
        Add-Type -TypeDefinition $mockProbeSource -Language CSharp -OutputAssembly $mockProbePath -OutputType ConsoleApplication

        $probeConfigPath = Join-Path $probeRoot "inventory.config.json"
        $probeConfig = [ordered]@{
            roots = @(
                [ordered]@{ name = "Standard"; path = $probeStandard; classificationHint = "1080p" },
                [ordered]@{ name = "UHD"; path = $probeUhd; classificationHint = "2160p" },
                [ordered]@{ name = "3D"; path = $probeThreeD; classificationHint = "3D" }
            )
            outputDirectory = $probeOutput
            target = [ordered]@{
                moviesRoot = (Join-Path $probeRoot "target")
                qualityFolders = [ordered]@{ "1080p" = "1080p"; "2160p" = "2160p"; "3D" = "3D" }
            }
            videoExtensions = @(".mp4")
            subtitleExtensions = @(".srt")
            hashDuplicateCandidates = $false
            ffprobeTimeoutSeconds = 1
            ffprobeProbeSizeBytes = 1048576
            ffprobeAnalyzeDurationMicroseconds = 1000000
            ffprobeErrorSummaryLines = 3
        }
        $probeConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $probeConfigPath -Encoding UTF8

        $probeResult = & $inventoryScript -ConfigPath $probeConfigPath -FfprobeExecutable $mockProbePath
        $probeInventory = Get-Content -LiteralPath $probeResult.InventoryJson -Raw | ConvertFrom-Json
        Assert-True -Condition ($probeInventory.ItemCount -eq 2) -Message "inventory continues after malformed and timed-out probes"
        $malformedItem = $probeInventory.Items | Where-Object FileName -eq "Malformed Movie (2002).mp4"
        $timeoutItem = $probeInventory.Items | Where-Object FileName -eq "Timeout Movie (2003).mp4"
        Assert-True -Condition ($malformedItem.ProbeStatus -eq "CompletedWithStreamErrors") -Message "successful probe with malformed H.264 stderr is flagged"
        Assert-True -Condition ($malformedItem.ProbeStderrLineCount -eq 200) -Message "repeated stderr is counted without being emitted"
        Assert-True -Condition ($malformedItem.ProbeStderrSummary.Length -lt 2000) -Message "stderr report is bounded"
        Assert-True -Condition (@($malformedItem.ReviewReasons | Where-Object { $_ -match "malformed media stream" }).Count -eq 1) -Message "malformed stream enters manual review"
        Assert-True -Condition ($timeoutItem.ProbeStatus -eq "TimedOut") -Message "hung probe is terminated by the configured timeout"
        Assert-True -Condition (@($timeoutItem.ReviewReasons | Where-Object { $_ -match "timed out" }).Count -eq 1) -Message "probe timeout enters manual review"
    }

    Write-Host "Media planning fixture checks passed."
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

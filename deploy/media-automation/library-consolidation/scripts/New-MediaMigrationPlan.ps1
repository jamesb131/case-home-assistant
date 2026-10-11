[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InventoryPath,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-ObjectProperty {
    param(
        [AllowNull()][object]$Object,
        [string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function ConvertTo-SafeName {
    param([string]$Value)

    $clean = [regex]::Replace($Value, '[<>:"/\\|?*]', ' ')
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim().TrimEnd([char[]]@('.'))
    return $clean
}

function Escape-Markdown {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return "" }
    return "$Value".Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
}

if (-not (Test-Path -LiteralPath $InventoryPath -PathType Leaf)) { throw "Inventory file not found: $InventoryPath" }
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Configuration file not found: $ConfigPath" }

$inventory = Get-Content -LiteralPath (Resolve-Path -LiteralPath $InventoryPath).Path -Raw | ConvertFrom-Json
$config = Get-Content -LiteralPath (Resolve-Path -LiteralPath $ConfigPath).Path -Raw | ConvertFrom-Json
$target = Get-ObjectProperty -Object $config -Name "target"
$moviesRoot = "$(Get-ObjectProperty -Object $target -Name 'moviesRoot' -Default '')".Trim()
$qualityFolders = Get-ObjectProperty -Object $target -Name "qualityFolders"
if (-not $moviesRoot -or $moviesRoot -match '(?i)replace_with|change[_-]?me') { throw "Configure target.moviesRoot before creating a plan." }

$baseOutput = if ($OutputDirectory) { $OutputDirectory } else { Split-Path -Parent (Resolve-Path -LiteralPath $InventoryPath).Path }
if (-not (Test-Path -LiteralPath $baseOutput -PathType Container)) {
    New-Item -ItemType Directory -Path $baseOutput -Force | Out-Null
}
$runDirectory = Join-Path $baseOutput ("migration-plan-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

$planItems = @()
foreach ($item in @(Get-ObjectProperty -Object $inventory -Name "Items" -Default @())) {
    $reasons = @()
    $classification = $null
    if (Get-ObjectProperty -Object $item -Name "ThreeDFormat") {
        $classification = "3D"
    }
    elseif ((Get-ObjectProperty -Object $item -Name "ResolutionClass") -eq "2160p") {
        $classification = "2160p"
    }
    elseif ((Get-ObjectProperty -Object $item -Name "ResolutionClass") -eq "1080p") {
        $classification = "1080p"
    }
    else {
        $hint = Get-ObjectProperty -Object $item -Name "CollectionHint"
        if ($hint -in @("1080p", "2160p", "3D")) {
            $classification = $hint
            $reasons += "Classification relies on the source collection hint"
        }
        else {
            $reasons += "Target quality could not be classified"
        }
    }

    $title = ConvertTo-SafeName -Value "$(Get-ObjectProperty -Object $item -Name 'Title' -Default '')"
    $year = Get-ObjectProperty -Object $item -Name "Year"
    if (-not $title) { $reasons += "Title is missing" }
    if (-not $year) { $reasons += "Release year is missing" }

    $edition = "$(Get-ObjectProperty -Object $item -Name 'Edition' -Default '')".Trim()
    $threeDFormat = "$(Get-ObjectProperty -Object $item -Name 'ThreeDFormat' -Default '')".Trim()
    if ($classification -eq "3D") {
        if (-not $edition) { $edition = "3D" }
        elseif ($edition -notmatch '(?i)\b3D\b') { $edition = "$edition 3D" }
        if ($threeDFormat -and $threeDFormat -ne "Unknown 3D" -and $edition -notmatch ([regex]::Escape($threeDFormat))) {
            $edition = "$edition $threeDFormat"
        }
    }
    $edition = ConvertTo-SafeName -Value $edition

    $baseName = if ($title -and $year) { "$title ($year)" } elseif ($title) { $title } else { "UNCLASSIFIED-$($item.Id)" }
    if ($edition) { $baseName += " {edition-$edition}" }

    $qualityFolder = if ($classification) { "$(Get-ObjectProperty -Object $qualityFolders -Name $classification -Default '')".Trim() } else { $null }
    if ($classification -and -not $qualityFolder) { $reasons += "No target folder is configured for $classification" }

    $destinationFolder = if ($qualityFolder) { Join-Path (Join-Path $moviesRoot $qualityFolder) $baseName } else { $null }
    $destinationVideo = if ($destinationFolder) { Join-Path $destinationFolder "$baseName$($item.Extension)" } else { $null }

    $subtitlePlans = @()
    foreach ($subtitle in @(Get-ObjectProperty -Object $item -Name "ExternalSubtitles" -Default @())) {
        $suffix = @()
        $language = "$(Get-ObjectProperty -Object $subtitle -Name 'Language' -Default '')".Trim()
        if ($language) { $suffix += $language } else { $reasons += "Subtitle language requires review: $($subtitle.FileName)" }
        if ([bool](Get-ObjectProperty -Object $subtitle -Name "Forced" -Default $false)) { $suffix += "forced" }
        elseif ([bool](Get-ObjectProperty -Object $subtitle -Name "SDH" -Default $false)) { $suffix += "sdh" }
        $suffixText = if ($suffix.Count -gt 0) { "." + ($suffix -join ".") } else { "" }
        $subtitlePlans += [pscustomobject]@{
            SourcePath = $subtitle.Path
            DestinationPath = if ($destinationFolder) { Join-Path $destinationFolder "$baseName$suffixText$($subtitle.Extension)" } else { $null }
            Language = $language
            Forced = [bool]$subtitle.Forced
            SDH = [bool]$subtitle.SDH
        }
    }

    foreach ($sourceReason in @(Get-ObjectProperty -Object $item -Name "ReviewReasons" -Default @())) {
        $reasons += "Inventory: $sourceReason"
    }
    if (Get-ObjectProperty -Object $item -Name "SuspectedDuplicateGroup") { $reasons += "Same-title, same-size duplicate candidate requires review" }
    if (Get-ObjectProperty -Object $item -Name "ConfirmedDuplicateGroup") { $reasons += "SHA-256-identical duplicate requires an explicit keep decision" }

    $planItems += [pscustomobject]@{
        Id = $item.Id
        SourcePath = $item.FullPath
        SourceCollection = $item.Collection
        Title = $title
        Year = $year
        Edition = $edition
        Classification = $classification
        DestinationFolder = $destinationFolder
        DestinationVideoPath = $destinationVideo
        SubtitlePlans = $subtitlePlans
        SuspectedDuplicateGroup = $item.SuspectedDuplicateGroup
        ConfirmedDuplicateGroup = $item.ConfirmedDuplicateGroup
        DestinationCollision = $false
        Confidence = if ($reasons.Count -eq 0) { "High" } else { "Review" }
        ManualReview = [bool]($reasons.Count -gt 0)
        ReviewReasons = @($reasons | Select-Object -Unique)
        ProposedAction = "Move"
    }
}

$collisionGroups = @($planItems | Where-Object DestinationVideoPath | Group-Object { $_.DestinationVideoPath.ToLowerInvariant() } | Where-Object Count -gt 1)
foreach ($group in $collisionGroups) {
    foreach ($item in $group.Group) {
        $item.DestinationCollision = $true
        $item.ManualReview = $true
        $item.Confidence = "Review"
        $item.ProposedAction = "Hold"
        $item.ReviewReasons = @(($item.ReviewReasons + "Proposed destination collides with another inventory item") | Select-Object -Unique)
    }
}

$generatedAt = (Get-Date).ToUniversalTime().ToString("o")
$document = [ordered]@{
    SchemaVersion = 1
    GeneratedAtUtc = $generatedAt
    Tool = "New-MediaMigrationPlan.ps1"
    PlanningOnly = $true
    SourceInventory = (Resolve-Path -LiteralPath $InventoryPath).Path
    TargetMoviesRoot = $moviesRoot
    ItemCount = $planItems.Count
    CollisionCount = $collisionGroups.Count
    Items = $planItems
}

$jsonPath = Join-Path $runDirectory "media-migration-plan.json"
$csvPath = Join-Path $runDirectory "media-migration-plan.csv"
$summaryPath = Join-Path $runDirectory "media-migration-plan.md"
$reviewPath = Join-Path $runDirectory "manual-review.csv"
$document | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$rows = @($planItems | ForEach-Object {
    [pscustomobject]@{
        Id = $_.Id
        SourcePath = $_.SourcePath
        DestinationVideoPath = $_.DestinationVideoPath
        Classification = $_.Classification
        Title = $_.Title
        Year = $_.Year
        Edition = $_.Edition
        ProposedAction = $_.ProposedAction
        Confidence = $_.Confidence
        DestinationCollision = $_.DestinationCollision
        SubtitleCount = $_.SubtitlePlans.Count
        ReviewReasons = ($_.ReviewReasons -join "; ")
    }
})
if ($rows.Count -gt 0) { $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 }
else { '"Id","SourcePath","DestinationVideoPath","Classification","Title","Year","Edition","ProposedAction","Confidence","DestinationCollision","SubtitleCount","ReviewReasons"' | Set-Content -LiteralPath $csvPath -Encoding UTF8 }

$reviewRows = @($rows | Where-Object { $_.Confidence -eq "Review" })
if ($reviewRows.Count -gt 0) { $reviewRows | Export-Csv -LiteralPath $reviewPath -NoTypeInformation -Encoding UTF8 }
else { '"Id","SourcePath","DestinationVideoPath","Classification","Title","Year","Edition","ProposedAction","Confidence","DestinationCollision","SubtitleCount","ReviewReasons"' | Set-Content -LiteralPath $reviewPath -Encoding UTF8 }

$markdown = [System.Collections.Generic.List[string]]::new()
$markdown.Add("# Media migration plan")
$markdown.Add("")
$markdown.Add("Generated: $generatedAt")
$markdown.Add("")
$markdown.Add("Planning only. This script did not move, rename, copy or delete any media.")
$markdown.Add("")
$markdown.Add("- Planned items: $($planItems.Count)")
$markdown.Add("- High-confidence proposals: $(@($planItems | Where-Object Confidence -eq 'High').Count)")
$markdown.Add("- Manual-review proposals: $($reviewRows.Count)")
$markdown.Add("- Destination collision groups: $($collisionGroups.Count)")
$markdown.Add("")
$markdown.Add("| Source | Proposed destination | Class | Action | Confidence | Notes |")
$markdown.Add("| --- | --- | --- | --- | --- | --- |")
foreach ($item in $planItems) {
    $markdown.Add("| $(Escape-Markdown $item.SourcePath) | $(Escape-Markdown $item.DestinationVideoPath) | $($item.Classification) | $($item.ProposedAction) | $($item.Confidence) | $(Escape-Markdown ($item.ReviewReasons -join '; ')) |")
}
$markdown | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "Migration plan complete: $runDirectory"
Write-Host "No source files were modified. No migration was executed."

[pscustomobject]@{
    OutputDirectory = $runDirectory
    PlanJson = $jsonPath
    PlanCsv = $csvPath
    SummaryMarkdown = $summaryPath
    ManualReviewCsv = $reviewPath
    ItemCount = $planItems.Count
}

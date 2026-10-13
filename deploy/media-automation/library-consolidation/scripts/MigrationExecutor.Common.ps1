$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-MigrationProperty {
    param([AllowNull()][object]$Object, [string]$Name, [AllowNull()][object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Get-NormalizedMigrationPath {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $value = $Path.Trim().Trim('"').Replace('/', [IO.Path]::DirectorySeparatorChar)
    if ($value.StartsWith('\\?\')) { $value = $value.Substring(4) }
    try { $value = [IO.Path]::GetFullPath($value) } catch { }
    return $value.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)).Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
}

function Get-Sha256Text {
    param([string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-MigrationOperationsDigest {
    param([object[]]$Operations)
    $lines = @($Operations | Sort-Object Sequence | ForEach-Object {
        "$($_.Sequence)|$($_.OperationId)|$($_.InventoryId)|$($_.Kind)|$($_.SourcePath)|$($_.DestinationPath)|$($_.ExpectedSizeBytes)|$($_.ExpectedSha256)"
    })
    return Get-Sha256Text ($lines -join "`n")
}

function Get-MigrationItemIdDigest {
    param([object[]]$Items)
    return Get-Sha256Text ((@($Items | ForEach-Object { "$(Get-MigrationProperty $_ 'InventoryId' '')" } | Sort-Object) -join "`n"))
}

function Get-MigrationExcludedEvidenceDigest {
    param([object[]]$Evidence)
    $lines = @($Evidence | Sort-Object InventoryId | ForEach-Object { "$($_.InventoryId)|$($_.SourcePath)|$($_.ExpectedSizeBytes)|$($_.ExpectedSha256)" })
    return Get-Sha256Text ($lines -join "`n")
}

function Get-FileSha256Lower {
    param([string]$Path)
    return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash).ToLowerInvariant()
}

function Test-SameMigrationVolume {
    param([string]$SourcePath, [string]$DestinationPath)
    $getVolume = Get-Command Get-Volume -ErrorAction SilentlyContinue
    if ($getVolume) {
        $sourceProbe = if (Test-Path -LiteralPath $SourcePath) { $SourcePath } else { Split-Path -Parent $SourcePath }
        $destinationProbe = if (Test-Path -LiteralPath $DestinationPath) { $DestinationPath } else { Split-Path -Parent $DestinationPath }
        while ($sourceProbe -and -not (Test-Path -LiteralPath $sourceProbe)) { $sourceProbe = Split-Path -Parent $sourceProbe }
        while ($destinationProbe -and -not (Test-Path -LiteralPath $destinationProbe)) { $destinationProbe = Split-Path -Parent $destinationProbe }
        if ($sourceProbe -and $destinationProbe) {
            try {
                $sourceVolume = Get-Volume -FilePath $sourceProbe -ErrorAction Stop
                $destinationVolume = Get-Volume -FilePath $destinationProbe -ErrorAction Stop
                $sourceIdentity = if ($sourceVolume.UniqueId) { "$($sourceVolume.UniqueId)" } else { "$($sourceVolume.DriveLetter)" }
                $destinationIdentity = if ($destinationVolume.UniqueId) { "$($destinationVolume.UniqueId)" } else { "$($destinationVolume.DriveLetter)" }
                if ($sourceIdentity -and $destinationIdentity) { return [string]::Equals($sourceIdentity, $destinationIdentity, [StringComparison]::OrdinalIgnoreCase) }
            }
            catch { }
        }
    }
    $sourceRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($SourcePath))
    $destinationRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($DestinationPath))
    return [string]::Equals($sourceRoot, $destinationRoot, [StringComparison]::OrdinalIgnoreCase)
}

function Test-MigrationPathWithin {
    param([string]$Path, [string]$Root)
    $pathKey = Get-NormalizedMigrationPath $Path
    $rootKey = Get-NormalizedMigrationPath $Root
    if (-not $pathKey -or -not $rootKey) { return $false }
    $separator = [IO.Path]::DirectorySeparatorChar
    return [bool]($pathKey -eq $rootKey -or $pathKey.StartsWith("$rootKey$separator", [StringComparison]::OrdinalIgnoreCase))
}

function Read-MigrationManifest {
    param([string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Migration manifest not found: $ManifestPath" }
    $resolved = (Resolve-Path -LiteralPath $ManifestPath).Path
    $manifest = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool](Get-MigrationProperty $manifest 'PlanningOnly' $false)) { throw 'Manifest is not marked PlanningOnly.' }
    $items = @(Get-MigrationProperty $manifest 'Items' @())
    $declared = [int](Get-MigrationProperty $manifest 'ItemCount' -1)
    if ($declared -lt 0 -or $declared -ne @($items).Count) { throw "Manifest item count is invalid: declared $declared, parsed $(@($items).Count)." }
    $ready = @($items | Where-Object { "$(Get-MigrationProperty $_ 'Status' '')" -eq 'Ready' })
    $excluded = @($items | Where-Object { "$(Get-MigrationProperty $_ 'Status' '')" -ne 'Ready' })
    if ([int](Get-MigrationProperty $manifest 'ReadyCount' -1) -ne @($ready).Count) { throw 'Manifest ReadyCount does not match its item statuses.' }
    if (([int](Get-MigrationProperty $manifest 'ReviewCount' -1) + [int](Get-MigrationProperty $manifest 'BlockedCount' -1)) -ne @($excluded).Count) { throw 'Manifest excluded counts do not match Review plus Blocked items.' }
    $targetMoviesRoot = "$(Get-MigrationProperty $manifest 'TargetMoviesRoot' '')".Trim()
    if (-not $targetMoviesRoot) { throw 'Manifest TargetMoviesRoot is missing.' }
    return [pscustomobject]@{
        Path = $resolved
        Sha256 = Get-FileSha256Lower $resolved
        Manifest = $manifest
        Items = $items
        ReadyItems = $ready
        ExcludedItems = $excluded
        TargetMoviesRoot = $targetMoviesRoot
    }
}

function Get-ExpectedPlexLibrary {
    param([string]$Classification)
    switch ($Classification) {
        '1080p' { return 'Movies' }
        '2160p' { return 'Movies 4K' }
        '3D' { return 'Movies 3D' }
        default { return $null }
    }
}

function New-MigrationOperations {
    param([object[]]$ReadyItems, [switch]$CaptureSidecarMetadata)
    $operations = [Collections.Generic.List[object]]::new()
    $sequence = 0
    $itemIndex = 0
    foreach ($item in $ReadyItems) {
        $itemIndex++
        $inventoryId = "$(Get-MigrationProperty $item 'InventoryId' '')"
        $videoSource = "$(Get-MigrationProperty $item 'SourcePath' '')"
        $videoDestination = "$(Get-MigrationProperty $item 'DestinationVideoPath' '')"
        if ($CaptureSidecarMetadata) { Write-Progress -Activity 'Capturing migration hash evidence' -Status "$itemIndex / $(@($ReadyItems).Count): $videoSource" -PercentComplete (($itemIndex / [math]::Max(1, @($ReadyItems).Count)) * 100) }
        foreach ($sidecar in @(Get-MigrationProperty $item 'SubtitlePlans' @())) {
            $source = "$(Get-MigrationProperty $sidecar 'SourcePath' '')"
            $destination = "$(Get-MigrationProperty $sidecar 'DestinationPath' '')"
            $size = [int64]0
            $hash = ''
            if ($CaptureSidecarMetadata -and (Test-Path -LiteralPath $source -PathType Leaf)) {
                $file = Get-Item -LiteralPath $source
                $size = [int64]$file.Length
                $hash = Get-FileSha256Lower $source
            }
            $sequence++
            $key = "$inventoryId|Sidecar|$source|$destination"
            $operations.Add([pscustomobject]@{
                Sequence = $sequence; OperationId = Get-Sha256Text $key; InventoryId = $inventoryId; Kind = 'Sidecar'
                SourcePath = $source; DestinationPath = $destination; ExpectedSizeBytes = $size; ExpectedSha256 = $hash; ManifestExpectedSha256 = ''
            })
        }
        # Move the video last. A movie-folder operation is not atomic, but this keeps
        # the primary file at its original path until all approved sidecars are placed.
        $manifestVideoHash = "$(Get-MigrationProperty $item 'Sha256' '')".ToLowerInvariant()
        $videoHash = $manifestVideoHash
        if ($CaptureSidecarMetadata -and (Test-Path -LiteralPath $videoSource -PathType Leaf)) { $videoHash = Get-FileSha256Lower $videoSource }
        $sequence++
        $videoKey = "$inventoryId|Video|$videoSource|$videoDestination"
        $operations.Add([pscustomobject]@{
            Sequence = $sequence; OperationId = Get-Sha256Text $videoKey; InventoryId = $inventoryId; Kind = 'Video'
            SourcePath = $videoSource; DestinationPath = $videoDestination
            ExpectedSizeBytes = [int64](Get-MigrationProperty $item 'SizeBytes' 0)
            ExpectedSha256 = $videoHash; ManifestExpectedSha256 = $manifestVideoHash
        })
    }
    if ($CaptureSidecarMetadata) { Write-Progress -Activity 'Capturing migration hash evidence' -Completed }
    return @($operations)
}

function Test-FileAgainstOperation {
    param([string]$Path, [object]$Operation, [switch]$RequireHash)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [pscustomobject]@{ Passed = $false; Reason = 'File is missing' } }
    $file = Get-Item -LiteralPath $Path
    $expectedSize = [int64](Get-MigrationProperty $Operation 'ExpectedSizeBytes' 0)
    if ($expectedSize -gt 0 -and [int64]$file.Length -ne $expectedSize) { return [pscustomobject]@{ Passed = $false; Reason = "Size is $($file.Length), expected $expectedSize" } }
    $expectedHash = "$(Get-MigrationProperty $Operation 'ExpectedSha256' '')".ToLowerInvariant()
    if ($RequireHash -and -not $expectedHash) { return [pscustomobject]@{ Passed = $false; Reason = 'Expected SHA-256 is unavailable' } }
    if ($expectedHash) {
        $actualHash = Get-FileSha256Lower $Path
        if ($actualHash -ne $expectedHash) { return [pscustomobject]@{ Passed = $false; Reason = "SHA-256 differs from approved value ($actualHash)" } }
    }
    return [pscustomobject]@{ Passed = $true; Reason = 'Size and available hash evidence match' }
}

function Add-MigrationJournalRecord {
    param([string]$JournalPath, [hashtable]$Record)
    $parent = Split-Path -Parent $JournalPath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $Record['RecordedAtUtc'] = (Get-Date).ToUniversalTime().ToString('o')
    $line = ([pscustomobject]$Record | ConvertTo-Json -Compress -Depth 10) + [Environment]::NewLine
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($line)
    $stream = [IO.FileStream]::new($JournalPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read, 4096, [IO.FileOptions]::WriteThrough)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}

function Read-MigrationJournal {
    param([string]$JournalPath)
    if (-not (Test-Path -LiteralPath $JournalPath -PathType Leaf)) { return @() }
    $records = [Collections.Generic.List[object]]::new()
    $lineNumber = 0
    foreach ($line in [IO.File]::ReadLines($JournalPath)) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $records.Add(($line | ConvertFrom-Json)) }
        catch { throw "Journal is invalid at line ${lineNumber}: $($_.Exception.Message)" }
    }
    return @($records)
}

function Test-PlexRunning {
    $plexNames = @('Plex Media Server', 'Plex Media Scanner', 'PlexScriptHost', 'PlexMediaServer', 'Plex Transcoder')
    foreach ($name in $plexNames) {
        if (Get-Process -Name $name -ErrorAction SilentlyContinue) { return $true }
    }
    return $false
}

function Write-MigrationCsv {
    param([object[]]$Rows, [string]$Path, [string]$Header)
    if (@($Rows).Count -gt 0) { $Rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 }
    else { $Header | Set-Content -LiteralPath $Path -Encoding UTF8 }
}

function Escape-MigrationMarkdown {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return "$Value".Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

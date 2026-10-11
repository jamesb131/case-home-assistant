[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [string]$OutputDirectory,

    [switch]$HashDuplicateCandidates,

    [switch]$SkipFfprobe
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

function Get-NormalizedPath {
    param([string]$Path)
    $separators = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd($separators)
}

function Test-PathWithin {
    param(
        [string]$Candidate,
        [string]$Parent
    )

    $candidatePath = Get-NormalizedPath -Path $Candidate
    $parentPath = Get-NormalizedPath -Path $Parent
    if ($candidatePath.Equals($parentPath, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $candidatePath.StartsWith("$parentPath$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-StableId {
    param([string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant())
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash).Replace("-", "").Substring(0, 16).ToLowerInvariant())
    }
    finally {
        $sha.Dispose()
    }
}

function ConvertTo-CleanTitle {
    param([string]$Value)

    $clean = $Value
    $clean = [regex]::Replace($clean, '\{edition-[^}]+\}', '', 'IgnoreCase')
    $clean = [regex]::Replace($clean, '\[[^\]]*\]', ' ')
    $clean = [regex]::Replace($clean, '[._]+', ' ')
    $clean = [regex]::Replace($clean, '\b(2160p|1080p|720p|576p|480p|uhd|bluray|blu-ray|bdrip|brrip|webrip|web-dl|webdl|hdtv|remux|x264|x265|h264|h265|hevc|av1|hdr10\+?|dolby[ ._-]?vision|dovi|sbs|hsbs|fsbs|tab|hou|3d)\b.*$', '', 'IgnoreCase')
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim().Trim([char[]]@('-', '_', '.'))
    return $clean
}

function Get-MovieIdentity {
    param(
        [System.IO.FileInfo]$File,
        [string]$RootPath
    )

    $folderName = $File.Directory.Name
    $rootLeaf = (Get-Item -LiteralPath $RootPath).Name
    $candidate = if ($folderName -and $folderName -ne $rootLeaf) { $folderName } else { $File.BaseName }
    $combined = "$candidate $($File.BaseName)"

    $edition = $null
    $editionMatch = [regex]::Match($combined, '\{edition-(?<edition>[^}]+)\}', 'IgnoreCase')
    if ($editionMatch.Success) {
        $edition = $editionMatch.Groups['edition'].Value.Trim()
    }
    else {
        $knownEdition = [regex]::Match($combined, '\b(Director(?:''s)? Cut|Extended(?: Edition| Cut)?|Final Cut|Theatrical(?: Cut)?|Unrated|Special Edition|IMAX|3D)\b', 'IgnoreCase')
        if ($knownEdition.Success) { $edition = $knownEdition.Value.Trim() }
    }

    $year = $null
    $yearMatch = [regex]::Match($candidate, '(?<!\d)(?<year>(?:19|20)\d{2})(?!\d)')
    if (-not $yearMatch.Success) {
        $yearMatch = [regex]::Match($File.BaseName, '(?<!\d)(?<year>(?:19|20)\d{2})(?!\d)')
    }
    if ($yearMatch.Success) { $year = [int]$yearMatch.Groups['year'].Value }

    $titleSource = $candidate
    if ($yearMatch.Success -and $candidate.Contains($yearMatch.Value)) {
        $titleSource = $candidate.Substring(0, $candidate.IndexOf($yearMatch.Value, [System.StringComparison]::OrdinalIgnoreCase))
    }
    $title = ConvertTo-CleanTitle -Value $titleSource
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = ConvertTo-CleanTitle -Value $File.BaseName
    }

    $keyTitle = [regex]::Replace($title.ToLowerInvariant(), '[^a-z0-9]+', '')
    $matchKey = if ($keyTitle -and $year) { "$keyTitle-$year" } else { $null }

    return [pscustomobject]@{
        Title = $title
        Year = $year
        Edition = $edition
        MatchKey = $matchKey
    }
}

function Invoke-Ffprobe {
    param(
        [string]$Executable,
        [string]$MediaPath
    )

    $escapedPath = $MediaPath.Replace('"', '\"')
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.Arguments = "-v error -show_format -show_streams -print_format json `"$escapedPath`""
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{ Success = $false; Data = $null; Error = "ffprobe did not start" }
        }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            return [pscustomobject]@{ Success = $false; Data = $null; Error = "ffprobe exited $($process.ExitCode): $($stderr.Trim())" }
        }
        try {
            $data = $stdout | ConvertFrom-Json
            return [pscustomobject]@{ Success = $true; Data = $data; Error = $null }
        }
        catch {
            return [pscustomobject]@{ Success = $false; Data = $null; Error = "ffprobe returned invalid JSON: $($_.Exception.Message)" }
        }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Data = $null; Error = $_.Exception.Message }
    }
    finally {
        $process.Dispose()
    }
}

function Get-SubtitleDescriptor {
    param([System.IO.FileInfo]$File)

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    $tokens = @($stem -split '\.')
    $language = $null
    foreach ($token in $tokens) {
        if ($token -match '^[a-zA-Z]{2,3}(?:-[a-zA-Z]{2})?$') {
            $language = $token.ToLowerInvariant()
        }
    }
    return [pscustomobject]@{
        Path = $File.FullName
        FileName = $File.Name
        Extension = $File.Extension.ToLowerInvariant()
        Language = $language
        Forced = [bool]($stem -match '(?i)(?:^|[. _-])forced(?:$|[. _-])')
        SDH = [bool]($stem -match '(?i)(?:^|[. _-])(sdh|cc)(?:$|[. _-])')
    }
}

function Get-ResolutionClass {
    param(
        [AllowNull()][object]$Width,
        [AllowNull()][object]$Height,
        [string]$Fallback
    )

    $w = if ($null -ne $Width) { [int]$Width } else { 0 }
    $h = if ($null -ne $Height) { [int]$Height } else { 0 }
    if ($w -ge 3000 -or $h -ge 1600) { return "2160p" }
    if ($w -ge 1600 -or $h -ge 900) { return "1080p" }
    if ($w -ge 1100 -or $h -ge 650) { return "720p" }
    if ($w -gt 0 -or $h -gt 0) { return "SD" }
    return $Fallback
}

function Get-HdrClass {
    param([AllowNull()][object]$ProbeData)
    if ($null -eq $ProbeData) { return $null }

    $json = $ProbeData | ConvertTo-Json -Depth 20 -Compress
    if ($json -match '(?i)DOVI|Dolby Vision|dvhe|dvh1') { return "Dolby Vision" }
    if ($json -match '(?i)HDR10\+|Dynamic HDR10\+') { return "HDR10+" }
    if ($json -match '(?i)smpte2084') { return "HDR10/PQ" }
    if ($json -match '(?i)arib-std-b67') { return "HLG" }
    return $null
}

function Get-ThreeDFormat {
    param(
        [System.IO.FileInfo]$File,
        [AllowNull()][object]$ProbeData,
        [string]$Hint
    )

    $text = "$($File.DirectoryName) $($File.BaseName)"
    if ($null -ne $ProbeData) { $text += " " + ($ProbeData | ConvertTo-Json -Depth 20 -Compress) }
    if ($text -match '(?i)(?:^|[^a-z])(HSBS|SBS|side[ ._-]?by[ ._-]?side)(?:$|[^a-z])') { return "SBS" }
    if ($text -match '(?i)(?:^|[^a-z])(HOU|TAB|top[ ._-]?(?:and|bottom)|over[ ._-]?under)(?:$|[^a-z])') { return "Top-Bottom" }
    if ($text -match '(?i)(?:^|[^a-z])MVC(?:$|[^a-z])') { return "MVC" }
    if ($text -match '(?i)(?:^|[^a-z])3D(?:$|[^a-z])' -or $Hint -eq "3D") { return "Unknown 3D" }
    return $null
}

function Escape-Markdown {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return "" }
    return "$Value".Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Inventory configuration file not found: $ConfigPath"
}

$resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
$config = Get-Content -LiteralPath $resolvedConfigPath -Raw | ConvertFrom-Json
$roots = @(Get-ObjectProperty -Object $config -Name "roots" -Default @())
if ($roots.Count -lt 1) { throw "Configuration must contain at least one explicit media root." }

$requiredHints = @("1080p", "2160p", "3D")
$rootDetails = @()
foreach ($root in $roots) {
    $name = "$((Get-ObjectProperty -Object $root -Name 'name' -Default '') )".Trim()
    $path = "$((Get-ObjectProperty -Object $root -Name 'path' -Default '') )".Trim()
    $hint = "$((Get-ObjectProperty -Object $root -Name 'classificationHint' -Default '') )".Trim()
    if (-not $name -or -not $path -or -not $hint) { throw "Every root requires name, path and classificationHint." }
    if ($path -match '(?i)replace_with|change[_-]?me') { throw "Root '$name' still contains a placeholder path." }
    if ($hint -notin $requiredHints) { throw "Root '$name' has unsupported classificationHint '$hint'. Use 1080p, 2160p or 3D." }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Media root does not exist: $path" }
    $rootDetails += [pscustomobject]@{ Name = $name; Path = (Get-NormalizedPath -Path $path); ClassificationHint = $hint }
}

foreach ($requiredHint in $requiredHints) {
    if ($rootDetails.ClassificationHint -notcontains $requiredHint) {
        throw "Configuration must explicitly identify a $requiredHint collection. Confirm the actual 3D location rather than guessing it."
    }
}

for ($left = 0; $left -lt $rootDetails.Count; $left++) {
    for ($right = $left + 1; $right -lt $rootDetails.Count; $right++) {
        if ((Test-PathWithin -Candidate $rootDetails[$left].Path -Parent $rootDetails[$right].Path) -or (Test-PathWithin -Candidate $rootDetails[$right].Path -Parent $rootDetails[$left].Path)) {
            throw "Media roots overlap: '$($rootDetails[$left].Path)' and '$($rootDetails[$right].Path)'. Specify non-overlapping collection roots."
        }
    }
}

$baseOutput = if ($OutputDirectory) { $OutputDirectory } else { "$((Get-ObjectProperty -Object $config -Name 'outputDirectory' -Default '') )".Trim() }
if (-not $baseOutput) { throw "Set outputDirectory in the config or pass -OutputDirectory." }
foreach ($root in $rootDetails) {
    if ((Test-PathWithin -Candidate $baseOutput -Parent $root.Path) -or (Test-PathWithin -Candidate $root.Path -Parent $baseOutput)) {
        throw "Output directory must be completely outside every media root: $baseOutput"
    }
}

$runDirectory = Join-Path (Get-NormalizedPath -Path $baseOutput) ("inventory-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

$videoExtensions = @((Get-ObjectProperty -Object $config -Name "videoExtensions" -Default @(".mkv", ".mp4", ".m4v", ".avi")) | ForEach-Object { "$($_)".ToLowerInvariant() })
$subtitleExtensions = @((Get-ObjectProperty -Object $config -Name "subtitleExtensions" -Default @(".srt", ".ass", ".ssa", ".vtt")) | ForEach-Object { "$($_)".ToLowerInvariant() })
$configHashSetting = [bool](Get-ObjectProperty -Object $config -Name "hashDuplicateCandidates" -Default $false)
$hashCandidates = $HashDuplicateCandidates.IsPresent -or $configHashSetting

$ffprobeCommand = $null
if (-not $SkipFfprobe) {
    $ffprobeCommand = Get-Command ffprobe -ErrorAction SilentlyContinue
}
$ffprobePath = if ($ffprobeCommand) { $ffprobeCommand.Source } else { $null }

$records = @()
$unassociatedSubtitles = @()
foreach ($root in $rootDetails) {
    Write-Host "Scanning $($root.Name): $($root.Path)"
    $allFiles = @(Get-ChildItem -LiteralPath $root.Path -File -Recurse -Force -ErrorAction Stop)
    $videoFiles = @($allFiles | Where-Object { $videoExtensions -contains $_.Extension.ToLowerInvariant() })
    $subtitleFiles = @($allFiles | Where-Object { $subtitleExtensions -contains $_.Extension.ToLowerInvariant() })

    $subtitlesByDirectory = @{}
    foreach ($subtitle in $subtitleFiles) {
        if (-not $subtitlesByDirectory.ContainsKey($subtitle.DirectoryName)) { $subtitlesByDirectory[$subtitle.DirectoryName] = @() }
        $subtitlesByDirectory[$subtitle.DirectoryName] = @($subtitlesByDirectory[$subtitle.DirectoryName]) + $subtitle
    }
    $videosByDirectory = @{}
    foreach ($video in $videoFiles) {
        if (-not $videosByDirectory.ContainsKey($video.DirectoryName)) { $videosByDirectory[$video.DirectoryName] = @() }
        $videosByDirectory[$video.DirectoryName] = @($videosByDirectory[$video.DirectoryName]) + $video
    }

    foreach ($file in $videoFiles) {
        $identity = Get-MovieIdentity -File $file -RootPath $root.Path
        $reviewReasons = @()
        $pathSeparators = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $relativeDirectory = $file.DirectoryName.Substring($root.Path.Length).TrimStart($pathSeparators)
        $folderDepth = if ($relativeDirectory) { @($relativeDirectory -split '[\\/]' | Where-Object { $_ }).Count } else { 0 }
        if (-not $identity.Title) { $reviewReasons += "Title could not be inferred" }
        if (-not $identity.Year) { $reviewReasons += "Release year could not be inferred" }
        if ($file.Extension.ToLowerInvariant() -eq ".iso") { $reviewReasons += "Disk image requires special handling" }
        if ($folderDepth -eq 0) { $reviewReasons += "Video is stored directly in the collection root" }
        if ($folderDepth -gt 1) { $reviewReasons += "Video uses a nested folder layout" }

        $probe = $null
        if ($ffprobePath) {
            $probeResult = Invoke-Ffprobe -Executable $ffprobePath -MediaPath $file.FullName
            if ($probeResult.Success) { $probe = $probeResult.Data } else { $reviewReasons += "ffprobe failed: $($probeResult.Error)" }
        }
        elseif (-not $SkipFfprobe) {
            $reviewReasons += "ffprobe is not installed"
        }

        $streams = if ($probe) { @(Get-ObjectProperty -Object $probe -Name "streams" -Default @()) } else { @() }
        $videoStreams = @($streams | Where-Object { (Get-ObjectProperty -Object $_ -Name "codec_type") -eq "video" })
        $audioStreams = @($streams | Where-Object { (Get-ObjectProperty -Object $_ -Name "codec_type") -eq "audio" })
        $subtitleStreams = @($streams | Where-Object { (Get-ObjectProperty -Object $_ -Name "codec_type") -eq "subtitle" })
        $primaryVideo = if ($videoStreams.Count -gt 0) { $videoStreams[0] } else { $null }
        $width = Get-ObjectProperty -Object $primaryVideo -Name "width"
        $height = Get-ObjectProperty -Object $primaryVideo -Name "height"
        $resolutionClass = Get-ResolutionClass -Width $width -Height $height -Fallback $root.ClassificationHint
        $hdrClass = Get-HdrClass -ProbeData $probe
        $threeDFormat = Get-ThreeDFormat -File $file -ProbeData $probe -Hint $root.ClassificationHint

        if (-not $width -and $ffprobePath) { $reviewReasons += "Video dimensions are unavailable" }
        if ($root.ClassificationHint -eq "2160p" -and $width -and [int]$width -lt 3000) { $reviewReasons += "Resolution does not match the 2160p collection hint" }
        if ($root.ClassificationHint -eq "1080p" -and $width -and [int]$width -ge 3000) { $reviewReasons += "Resolution appears 4K inside the 1080p collection" }
        if ($root.ClassificationHint -eq "3D" -and $threeDFormat -eq "Unknown 3D") { $reviewReasons += "3D layout could not be classified" }

        $directorySubtitles = if ($subtitlesByDirectory.ContainsKey($file.DirectoryName)) { @($subtitlesByDirectory[$file.DirectoryName]) } else { @() }
        $sameFolderVideoCount = @($videosByDirectory[$file.DirectoryName]).Count
        $externalSubtitles = @()
        foreach ($subtitle in $directorySubtitles) {
            $subtitleStem = [System.IO.Path]::GetFileNameWithoutExtension($subtitle.Name)
            if ($sameFolderVideoCount -eq 1 -or $subtitleStem.StartsWith("$($file.BaseName).", [System.StringComparison]::OrdinalIgnoreCase) -or $subtitleStem.Equals($file.BaseName, [System.StringComparison]::OrdinalIgnoreCase)) {
                $descriptor = Get-SubtitleDescriptor -File $subtitle
                $externalSubtitles += $descriptor
                if (-not $descriptor.Language) { $reviewReasons += "External subtitle language is not identified: $($subtitle.Name)" }
            }
        }
        if ($sameFolderVideoCount -gt 1) { $reviewReasons += "Multiple video files share this folder" }

        $audioDetails = @($audioStreams | ForEach-Object {
            $tags = Get-ObjectProperty -Object $_ -Name "tags"
            [pscustomobject]@{
                Index = Get-ObjectProperty -Object $_ -Name "index"
                Codec = Get-ObjectProperty -Object $_ -Name "codec_name"
                Profile = Get-ObjectProperty -Object $_ -Name "profile"
                Channels = Get-ObjectProperty -Object $_ -Name "channels"
                ChannelLayout = Get-ObjectProperty -Object $_ -Name "channel_layout"
                Language = Get-ObjectProperty -Object $tags -Name "language"
                Title = Get-ObjectProperty -Object $tags -Name "title"
            }
        })
        $embeddedSubtitleDetails = @($subtitleStreams | ForEach-Object {
            $tags = Get-ObjectProperty -Object $_ -Name "tags"
            $disposition = Get-ObjectProperty -Object $_ -Name "disposition"
            [pscustomobject]@{
                Index = Get-ObjectProperty -Object $_ -Name "index"
                Codec = Get-ObjectProperty -Object $_ -Name "codec_name"
                Language = Get-ObjectProperty -Object $tags -Name "language"
                Title = Get-ObjectProperty -Object $tags -Name "title"
                Forced = [bool](Get-ObjectProperty -Object $disposition -Name "forced" -Default 0)
                Default = [bool](Get-ObjectProperty -Object $disposition -Name "default" -Default 0)
            }
        })

        $format = Get-ObjectProperty -Object $probe -Name "format"
        $records += [pscustomobject]@{
            Id = Get-StableId -Value $file.FullName
            Collection = $root.Name
            CollectionHint = $root.ClassificationHint
            RootPath = $root.Path
            FullPath = $file.FullName
            RelativePath = $file.FullName.Substring($root.Path.Length).TrimStart($pathSeparators)
            DirectoryPath = $file.DirectoryName
            FolderDepth = $folderDepth
            FileName = $file.Name
            Extension = $file.Extension.ToLowerInvariant()
            SizeBytes = [int64]$file.Length
            SizeGiB = [math]::Round($file.Length / 1GB, 3)
            LastWriteTimeUtc = $file.LastWriteTimeUtc.ToString("o")
            Title = $identity.Title
            Year = $identity.Year
            Edition = $identity.Edition
            MatchKey = $identity.MatchKey
            ResolutionClass = $resolutionClass
            Width = $width
            Height = $height
            VideoCodec = Get-ObjectProperty -Object $primaryVideo -Name "codec_name"
            VideoProfile = Get-ObjectProperty -Object $primaryVideo -Name "profile"
            PixelFormat = Get-ObjectProperty -Object $primaryVideo -Name "pix_fmt"
            FrameRate = Get-ObjectProperty -Object $primaryVideo -Name "avg_frame_rate"
            VideoBitRate = Get-ObjectProperty -Object $primaryVideo -Name "bit_rate"
            Container = Get-ObjectProperty -Object $format -Name "format_name"
            DurationSeconds = Get-ObjectProperty -Object $format -Name "duration"
            OverallBitRate = Get-ObjectProperty -Object $format -Name "bit_rate"
            HdrFormat = $hdrClass
            ThreeDFormat = $threeDFormat
            VersionGroup = $null
            VersionLabel = (@($resolutionClass, $hdrClass, $threeDFormat) | Where-Object { $_ } | Select-Object -Unique) -join " "
            AudioStreams = $audioDetails
            EmbeddedSubtitles = $embeddedSubtitleDetails
            ExternalSubtitles = $externalSubtitles
            SameFolderVideoCount = $sameFolderVideoCount
            SuspectedDuplicateGroup = $null
            ConfirmedDuplicateGroup = $null
            Sha256 = $null
            ReviewReasons = @($reviewReasons | Select-Object -Unique)
        }
    }

    foreach ($subtitle in $subtitleFiles) {
        $associated = $false
        $directoryVideos = if ($videosByDirectory.ContainsKey($subtitle.DirectoryName)) { @($videosByDirectory[$subtitle.DirectoryName]) } else { @() }
        $subtitleStem = [System.IO.Path]::GetFileNameWithoutExtension($subtitle.Name)
        foreach ($video in $directoryVideos) {
            if ($directoryVideos.Count -eq 1 -or $subtitleStem.StartsWith("$($video.BaseName).", [System.StringComparison]::OrdinalIgnoreCase) -or $subtitleStem.Equals($video.BaseName, [System.StringComparison]::OrdinalIgnoreCase)) {
                $associated = $true
                break
            }
        }
        if (-not $associated) {
            $descriptor = Get-SubtitleDescriptor -File $subtitle
            $unassociatedSubtitles += [pscustomobject]@{
                Id = Get-StableId -Value $subtitle.FullName
                Collection = $root.Name
                Path = $subtitle.FullName
                FileName = $subtitle.Name
                Extension = $descriptor.Extension
                Language = $descriptor.Language
                Forced = $descriptor.Forced
                SDH = $descriptor.SDH
                ReviewReason = "Subtitle could not be associated with exactly one video"
            }
        }
    }
}

$matchGroups = @($records | Where-Object { $_.MatchKey } | Group-Object MatchKey | Where-Object Count -gt 1)
foreach ($matchGroup in $matchGroups) {
    $versionGroupId = "version-$((Get-StableId -Value $matchGroup.Name))"
    foreach ($item in $matchGroup.Group) { $item.VersionGroup = $versionGroupId }
    $sizeGroups = @($matchGroup.Group | Group-Object SizeBytes | Where-Object Count -gt 1)
    foreach ($sizeGroup in $sizeGroups) {
        $suspectId = "suspect-$((Get-StableId -Value "$($matchGroup.Name)-$($sizeGroup.Name)"))"
        foreach ($item in $sizeGroup.Group) { $item.SuspectedDuplicateGroup = $suspectId }
        if ($hashCandidates) {
            foreach ($item in $sizeGroup.Group) {
                try { $item.Sha256 = (Get-FileHash -LiteralPath $item.FullPath -Algorithm SHA256).Hash.ToLowerInvariant() }
                catch { $item.ReviewReasons = @(($item.ReviewReasons + "SHA-256 failed: $($_.Exception.Message)") | Select-Object -Unique) }
            }
            $hashGroups = @($sizeGroup.Group | Where-Object Sha256 | Group-Object Sha256 | Where-Object Count -gt 1)
            foreach ($hashGroup in $hashGroups) {
                $confirmedId = "sha256-$($hashGroup.Name.Substring(0, 16))"
                foreach ($item in $hashGroup.Group) { $item.ConfirmedDuplicateGroup = $confirmedId }
            }
        }
    }
}

$generatedAt = (Get-Date).ToUniversalTime().ToString("o")
$inventoryDocument = [ordered]@{
    SchemaVersion = 1
    GeneratedAtUtc = $generatedAt
    Tool = "New-MediaInventory.ps1"
    ReadOnlySourceScan = $true
    FfprobeAvailable = [bool]$ffprobePath
    FfprobePath = $ffprobePath
    DuplicateCandidateHashing = $hashCandidates
    Roots = $rootDetails
    ItemCount = $records.Count
    UnassociatedSubtitleCount = $unassociatedSubtitles.Count
    UnassociatedSubtitles = $unassociatedSubtitles
    Items = $records
}

$jsonPath = Join-Path $runDirectory "media-inventory.json"
$csvPath = Join-Path $runDirectory "media-inventory.csv"
$summaryPath = Join-Path $runDirectory "media-inventory-summary.md"
$reviewCsvPath = Join-Path $runDirectory "manual-review.csv"
$reviewMarkdownPath = Join-Path $runDirectory "manual-review.md"

$inventoryDocument | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$csvRows = @($records | ForEach-Object {
    [pscustomobject]@{
        Id = $_.Id
        Collection = $_.Collection
        FullPath = $_.FullPath
        RelativePath = $_.RelativePath
        FileName = $_.FileName
        SizeBytes = $_.SizeBytes
        SizeGiB = $_.SizeGiB
        Title = $_.Title
        Year = $_.Year
        Edition = $_.Edition
        Resolution = $_.ResolutionClass
        Dimensions = if ($_.Width -and $_.Height) { "$($_.Width)x$($_.Height)" } else { $null }
        VideoCodec = $_.VideoCodec
        HdrFormat = $_.HdrFormat
        ThreeDFormat = $_.ThreeDFormat
        VersionGroup = $_.VersionGroup
        VersionLabel = $_.VersionLabel
        Audio = (($_.AudioStreams | ForEach-Object { "$($_.Language):$($_.Codec):$($_.ChannelLayout)" }) -join "; ")
        EmbeddedSubtitles = (($_.EmbeddedSubtitles | ForEach-Object { "$($_.Language):$($_.Codec)" }) -join "; ")
        ExternalSubtitles = (($_.ExternalSubtitles | ForEach-Object { "$($_.Language):$($_.FileName)" }) -join "; ")
        SuspectedDuplicateGroup = $_.SuspectedDuplicateGroup
        ConfirmedDuplicateGroup = $_.ConfirmedDuplicateGroup
        Sha256 = $_.Sha256
        ReviewReasons = ($_.ReviewReasons -join "; ")
    }
})
$csvHeader = '"Id","Collection","FullPath","RelativePath","FileName","SizeBytes","SizeGiB","Title","Year","Edition","Resolution","Dimensions","VideoCodec","HdrFormat","ThreeDFormat","VersionGroup","VersionLabel","Audio","EmbeddedSubtitles","ExternalSubtitles","SuspectedDuplicateGroup","ConfirmedDuplicateGroup","Sha256","ReviewReasons"'
if ($csvRows.Count -gt 0) {
    $csvRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
}
else {
    $csvHeader | Set-Content -LiteralPath $csvPath -Encoding UTF8
}

$reviewItems = @($records | Where-Object { $_.ReviewReasons.Count -gt 0 })
$reviewRows = @($reviewItems | ForEach-Object {
    [pscustomobject]@{ Id = $_.Id; Collection = $_.Collection; FullPath = $_.FullPath; Reasons = ($_.ReviewReasons -join "; ") }
})
$reviewRows += @($unassociatedSubtitles | ForEach-Object {
    [pscustomobject]@{ Id = $_.Id; Collection = $_.Collection; FullPath = $_.Path; Reasons = $_.ReviewReason }
})
if ($reviewRows.Count -gt 0) {
    $reviewRows | Export-Csv -LiteralPath $reviewCsvPath -NoTypeInformation -Encoding UTF8
}
else {
    '"Id","Collection","FullPath","Reasons"' | Set-Content -LiteralPath $reviewCsvPath -Encoding UTF8
}

$totalBytes = ($records | Measure-Object SizeBytes -Sum).Sum
if ($null -eq $totalBytes) { $totalBytes = 0 }
$suspectedGroups = @($records | ForEach-Object { $_.SuspectedDuplicateGroup } | Where-Object { $_ } | Select-Object -Unique)
$confirmedGroups = @($records | ForEach-Object { $_.ConfirmedDuplicateGroup } | Where-Object { $_ } | Select-Object -Unique)
$summary = [System.Collections.Generic.List[string]]::new()
$summary.Add("# Media inventory summary")
$summary.Add("")
$summary.Add("Generated: $generatedAt")
$summary.Add("")
$summary.Add("This report was produced by a read-only source scan. No media files were changed.")
$summary.Add("")
$summary.Add("## Totals")
$summary.Add("")
$summary.Add("- Video files: $($records.Count)")
$summary.Add("- Total size: $([math]::Round($totalBytes / 1TB, 3)) TiB")
$summary.Add("- Video items requiring review: $($reviewItems.Count)")
$summary.Add("- Unassociated subtitle files: $($unassociatedSubtitles.Count)")
$summary.Add("- Cross-root title/year groups: $($matchGroups.Count)")
$summary.Add("- Suspected same-size duplicate groups: $($suspectedGroups.Count)")
$summary.Add("- Confirmed SHA-256 duplicate groups: $($confirmedGroups.Count)")
$summary.Add("- ffprobe available: $([bool]$ffprobePath)")
$summary.Add("")
$summary.Add("## Collections")
$summary.Add("")
$summary.Add("| Collection | Hint | Files | Size TiB | Review |")
$summary.Add("| --- | --- | ---: | ---: | ---: |")
foreach ($root in $rootDetails) {
    $items = @($records | Where-Object Collection -eq $root.Name)
    $bytes = ($items | Measure-Object SizeBytes -Sum).Sum
    if ($null -eq $bytes) { $bytes = 0 }
    $reviewCount = @($items | Where-Object { $_.ReviewReasons.Count -gt 0 }).Count
    $summary.Add("| $(Escape-Markdown $root.Name) | $($root.ClassificationHint) | $($items.Count) | $([math]::Round($bytes / 1TB, 3)) | $reviewCount |")
}
$summary.Add("")
$summary.Add("## Version groups")
$summary.Add("")
if ($matchGroups.Count -eq 0) {
    $summary.Add("No repeated title/year groups were detected.")
}
else {
    $summary.Add("| Movie key | Files | Collections |")
    $summary.Add("| --- | ---: | --- |")
    foreach ($group in $matchGroups) {
        $collections = ($group.Group.Collection | Select-Object -Unique) -join ", "
        $summary.Add("| $(Escape-Markdown $group.Name) | $($group.Count) | $(Escape-Markdown $collections) |")
    }
}
$summary | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$reviewMarkdown = [System.Collections.Generic.List[string]]::new()
$reviewMarkdown.Add("# Manual review queue")
$reviewMarkdown.Add("")
$reviewMarkdown.Add("Generated: $generatedAt")
$reviewMarkdown.Add("")
if ($reviewRows.Count -eq 0) {
    $reviewMarkdown.Add("No automatically detected review items.")
}
else {
    $reviewMarkdown.Add("| ID | Collection | Path | Reasons |")
    $reviewMarkdown.Add("| --- | --- | --- | --- |")
    foreach ($item in $reviewItems) {
        $reviewMarkdown.Add("| $($item.Id) | $(Escape-Markdown $item.Collection) | $(Escape-Markdown $item.FullPath) | $(Escape-Markdown ($item.ReviewReasons -join '; ')) |")
    }
    foreach ($subtitle in $unassociatedSubtitles) {
        $reviewMarkdown.Add("| $($subtitle.Id) | $(Escape-Markdown $subtitle.Collection) | $(Escape-Markdown $subtitle.Path) | $(Escape-Markdown $subtitle.ReviewReason) |")
    }
}
$reviewMarkdown | Set-Content -LiteralPath $reviewMarkdownPath -Encoding UTF8

Write-Host "Inventory complete: $runDirectory"
Write-Host "No source files were modified."

[pscustomobject]@{
    OutputDirectory = $runDirectory
    InventoryJson = $jsonPath
    InventoryCsv = $csvPath
    SummaryMarkdown = $summaryPath
    ManualReviewCsv = $reviewCsvPath
    ManualReviewMarkdown = $reviewMarkdownPath
    ItemCount = $records.Count
}

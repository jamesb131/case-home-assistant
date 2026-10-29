[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectDirectory = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ImageName = 'case-nest10-sd-probe:1'

try {
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Desktop is not running.'
    }

    docker build -f (Join-Path $ProjectDirectory 'Dockerfile.sd-probe') -t $ImageName $ProjectDirectory
    if ($LASTEXITCODE -ne 0) {
        throw 'The SD probe builder image could not be built.'
    }

    docker run --rm `
        --network none `
        --mount "type=bind,source=$ProjectDirectory,target=/workspace" `
        --workdir /workspace `
        $ImageName `
        sh ./scripts/build-sd-probe.sh
    if ($LASTEXITCODE -ne 0) {
        throw 'The SD probe image build failed.'
    }
}
catch {
    Write-Error $_
    exit 1
}

Write-Host ''
Write-Host 'Probe image ready:'
Write-Host (Join-Path $ProjectDirectory 'output\images\sd-probe\nest10-sd-probe.img')
Write-Host 'The build does not write an SD card. Use a trusted graphical imager and verify the removable target.'

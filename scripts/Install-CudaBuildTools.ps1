# Build machine only; no NVIDIA driver is installed or changed.
[CmdletBinding()]
param([string]$ScratchDirectory = (Join-Path $env:TEMP 'lichtfeld-cuda-12.8'))
$ErrorActionPreference = 'Stop'
$lock = Get-Content (Join-Path $PSScriptRoot '..\upstream.lock.json') -Raw | ConvertFrom-Json
$cudaRoot = Join-Path $env:ProgramFiles 'NVIDIA GPU Computing Toolkit\CUDA\v12.8'
if (-not (Test-Path (Join-Path $cudaRoot 'bin\nvcc.exe'))) {
    New-Item -ItemType Directory -Path $ScratchDirectory -Force | Out-Null
    $installer = Join-Path $ScratchDirectory 'cuda_12.8.0_571.96_windows.exe'
    Invoke-WebRequest -Uri $lock.cudaInstaller -OutFile $installer
    $signature = Get-AuthenticodeSignature -LiteralPath $installer
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'NVIDIA') {
        throw "CUDA-installer heeft geen geldige NVIDIA-handtekening: $($signature.Status)"
    }
    $hash = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host "Official signed CUDA installer SHA256: $hash"
    $process = Start-Process -FilePath $installer -ArgumentList '-y -s -accepteula -toolkit -override -noDisplayDriver' -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -notin @(0,3010)) { throw "CUDA toolkit installatie mislukt: $($process.ExitCode)" }
    # Delete only the installer created by this script, never a computed tree.
    Remove-Item -LiteralPath $installer -Force
}
$nvcc = Join-Path $cudaRoot 'bin\nvcc.exe'
if (-not (Test-Path $nvcc)) { throw "nvcc ontbreekt na installatie: $nvcc" }
$version = & $nvcc --version
if ($LASTEXITCODE -ne 0 -or ($version -join "`n") -notmatch 'V12\.8\.61\b') {
    throw 'De bouw vereist de gepinde CUDA 12.8.0 compiler V12.8.61.'
}
$env:CUDA_PATH = $cudaRoot
$env:CUDA_PATH_V12_8 = $cudaRoot
$env:PATH = (Join-Path $cudaRoot 'bin') + ';' + $env:PATH
if ($env:GITHUB_ENV) {
    "CUDA_PATH=$cudaRoot" | Out-File $env:GITHUB_ENV -Encoding utf8 -Append
    "CUDA_PATH_V12_8=$cudaRoot" | Out-File $env:GITHUB_ENV -Encoding utf8 -Append
    (Join-Path $cudaRoot 'bin') | Out-File $env:GITHUB_PATH -Encoding utf8 -Append
}
$version | Write-Host

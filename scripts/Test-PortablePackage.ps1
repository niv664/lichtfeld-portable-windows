[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PackageRoot,
    [string]$ReportPath = (Join-Path $env:TEMP 'lichtfeld-package-tests.json'),
    [switch]$AllowMissingDriver
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $PackageRoot).Path
$required = @('bin/LichtFeld-Studio.exe','bin/python.exe','bin/python312.dll','bin/python312._pth',
    'bin/uv.exe','bin/lfs_core.dll','bin/lfs_python_runtime.dll','bin/lfs_visualizer.dll',
    'bin/lfs_mcp.dll','bin/_lfs_panel_contract.py','bin/lfs_splat_lod_hierarchy.py',
    'Lib/os.py','Lib/encodings/__init__.py','DLLs','share/LichtFeld-Studio/assets/fonts',
    'share/LichtFeld-Studio/assets/rmlui','share/LichtFeld-Studio/locales','LICENSE',
    'THIRD_PARTY_LICENSES.md','licenses','README-NL.md','SHA256SUMS.txt')
foreach ($relative in $required) { if (-not (Test-Path (Join-Path $root $relative))) { throw "Pakketbestand ontbreekt: $relative" } }
if (-not (Get-ChildItem (Join-Path $root 'bin') -Filter 'lichtfeld*.pyd')) { throw 'lichtfeld Python module ontbreekt' }
if (-not (Get-ChildItem (Join-Path $root 'bin') -Filter 'cudart64*.dll')) { throw 'CUDA-runtime DLL ontbreekt' }
if (-not (Get-ChildItem (Join-Path $root 'bin') -Filter 'curand64*.dll')) { throw 'cuRAND-runtime DLL ontbreekt' }
if (Get-ChildItem $root -Filter 'nvcuda.dll' -Recurse) { throw 'Driver DLL nvcuda.dll mag niet worden gebundeld' }
# Verify the exact bytes that will be distributed.
foreach ($line in Get-Content (Join-Path $root 'SHA256SUMS.txt')) {
    if ($line -notmatch '^([a-fA-F0-9]{64}) [ *](.+)$') { throw "Ongeldige checksumregel: $line" }
    $expected = $Matches[1]; $relative = $Matches[2]
    $file = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $file.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Checksum pad buiten pakket' }
    if ((Get-FileHash $file -Algorithm SHA256).Hash -ne $expected) { throw "Checksum mismatch: $relative" }
}
$peReport = Join-Path (Split-Path $ReportPath -Parent) 'pe-dependencies.json'
& (Join-Path $PSScriptRoot 'Test-PeDependencies.ps1') -PackageRoot $root -AdditionalSearchDirectory @((Join-Path $root 'DLLs'),(Join-Path $root 'extensions')) -JsonOutputPath $peReport -AllowMissingDriver:$AllowMissingDriver
if ($LASTEXITCODE -ne 0) { throw 'PE DLL dependencycontrole faalde' }
# A relocated copy and a Windows-only PATH prevent accidentally using build tools.
$relocation = Join-Path $env:TEMP ('lf relocated ' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $relocation | Out-Null
Copy-Item -Path (Join-Path $root '*') -Destination $relocation -Recurse
$oldPath = $env:PATH; $oldPythonHome = $env:PYTHONHOME; $oldPythonPath = $env:PYTHONPATH
$oldCuda = $env:CUDA_PATH; $oldVcpkg = $env:VCPKG_ROOT
$result = [ordered]@{checksums='passed'; requiredFiles='passed'; peImports='passed'; relocation=$relocation; gpuTraining='not run'; gui='not run'}
try {
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    $env:PYTHONHOME = $null; $env:PYTHONPATH = $null; $env:CUDA_PATH = $null; $env:VCPKG_ROOT = $null
    Push-Location $env:TEMP
    try {
        $python = Join-Path $relocation 'bin\python.exe'
        $code = "import sys,json,ssl,sqlite3,socket,ctypes,venv,zlib,_lfs_panel_contract,lfs_splat_lod_hierarchy; from pathlib import Path; root=Path(sys.executable).parent.parent.resolve(); assert all(Path(p).resolve().is_relative_to(root) for p in sys.path if p); print(json.dumps({'executable':sys.executable,'path':sys.path,'version':sys.version}))"
        $pythonOutput = & $python -I -B -c $code 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Embedded Python relocation faalde: $pythonOutput" }
        $result.pythonRelocation = 'passed'; $result.python = ($pythonOutput -join "`n")
        $uvOutput = & (Join-Path $relocation 'bin\uv.exe') --version 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Gebundelde uv start niet: $uvOutput" }
        $result.uv = ($uvOutput -join "`n")
        if (Test-Path (Join-Path $env:SystemRoot 'System32\nvcuda.dll')) {
            $help = & (Join-Path $relocation 'bin\LichtFeld-Studio.exe') --help 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Applicatie --help faalde: $help" }
            $result.applicationHelp = 'passed'
        } elseif ($AllowMissingDriver) {
            $result.applicationHelp = 'skipped: no NVIDIA driver on runner; CUDA driver DLL is a real system requirement'
        } else { throw 'NVIDIA-driver ontbreekt voor applicatie smoke test' }
    } finally { Pop-Location }
} finally {
    $env:PATH=$oldPath; $env:PYTHONHOME=$oldPythonHome; $env:PYTHONPATH=$oldPythonPath; $env:CUDA_PATH=$oldCuda; $env:VCPKG_ROOT=$oldVcpkg
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding utf8
    # This exact temporary directory was created above and is outside user data.
    $resolvedTemp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if ($relocation.StartsWith($resolvedTemp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $relocation -Leaf).StartsWith('lf relocated ')) {
        Remove-Item -LiteralPath $relocation -Recurse -Force
    }
}
$result | ConvertTo-Json -Depth 8

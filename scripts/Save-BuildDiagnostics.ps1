[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Workspace)
$ErrorActionPreference='Stop'
$Workspace=[IO.Path]::GetFullPath($Workspace)
$diagnostics=Join-Path $Workspace 'diagnostics'
New-Item -ItemType Directory -Path $diagnostics -Force | Out-Null
$files=@()
foreach($relative in @('b\CMakeCache.txt','b\CMakeFiles\CMakeConfigureLog.yaml','b\vcpkg-manifest-install.log','artifacts\package-tests.json','artifacts\pe-dependencies.json')){
    $path=Join-Path $Workspace $relative
    if(Test-Path -LiteralPath $path -PathType Leaf){$files+=Get-Item -LiteralPath $path}
}
if(Test-Path (Join-Path $Workspace 'logs')){$files+=Get-ChildItem (Join-Path $Workspace 'logs') -File}
$buildtrees=Join-Path $Workspace 'vcpkg\buildtrees'
if(Test-Path $buildtrees){
    # Only each port's top-level logs; never descend into src/reparsepoints.
    foreach($port in Get-ChildItem $buildtrees -Directory | Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0}){
        $files+=Get-ChildItem -LiteralPath $port.FullName -File -Filter '*.log'
    }
}
foreach($file in $files){
    if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
    $relative=[IO.Path]::GetRelativePath($Workspace,$file.FullName)
    $target=Join-Path $diagnostics $relative
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
}
$dist=Join-Path $Workspace 'dist'
if(Test-Path (Join-Path $dist 'bin\LichtFeld-Studio.exe')){
    # A diagnostic snapshot lets packaging-only failures be repaired and tested
    # without recompiling. This is explicitly not a validated public release.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $snapshot=Join-Path $diagnostics 'UNVALIDATED-portable-runtime.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($dist,$snapshot,[IO.Compression.CompressionLevel]::Optimal,$false)
    if((Get-Item $snapshot).Length -gt 400MB){
        # Keep diagnostics within the basic artifact allowance.
        Remove-Item -LiteralPath $snapshot -Force
        'Runtime snapshot exceeded 400 MiB; not uploaded. Full build logs remain available.' | Set-Content (Join-Path $diagnostics 'runtime-snapshot-omitted.txt')
    }
}
Get-ChildItem $diagnostics -Recurse -File | Measure-Object -Property Length -Sum | Select-Object Count,Sum

[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Workspace)
$ErrorActionPreference='Stop'
$Workspace=[IO.Path]::GetFullPath($Workspace)
$workspacePrefix=$Workspace.TrimEnd([char[]]'\/')+[IO.Path]::DirectorySeparatorChar
function Test-SafeWorkspacePath([string]$Path){
    $fullPath=[IO.Path]::GetFullPath($Path)
    if($fullPath -ne $Workspace -and -not $fullPath.StartsWith($workspacePrefix,[StringComparison]::OrdinalIgnoreCase)){return $false}
    # Check from the workspace downwards so a linked ancestor is rejected
    # before we inspect or enumerate its children. Missing output paths are OK.
    $cursor=$Workspace
    $parts=@('.')+@([IO.Path]::GetRelativePath($Workspace,$fullPath) -split '[\\/]' | Where-Object {$_ -ne '.'})
    foreach($part in $parts){
        if($part -ne '.'){$cursor=Join-Path $cursor $part}
        if(Test-Path -LiteralPath $cursor){
            if(((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
        }
    }
    return $true
}
function Test-NoReparseTree([string]$Root){
    if(-not (Test-SafeWorkspacePath $Root)){return $false}
    $pending=New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Root)
    while($pending.Count){
        foreach($item in Get-ChildItem -LiteralPath $pending.Pop() -Force){
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
            if($item.PSIsContainer){$pending.Push($item.FullName)}
        }
    }
    return $true
}
if(-not (Test-Path -LiteralPath $Workspace -PathType Container) -or -not (Test-SafeWorkspacePath $Workspace)){throw 'Diagnostics workspace must be an existing directory without a reparse point.'}
$diagnostics=Join-Path $Workspace 'diagnostics'
if(-not (Test-SafeWorkspacePath $diagnostics)){throw 'Diagnostics output path contains a reparse point.'}
if((Test-Path -LiteralPath $diagnostics) -and -not (Test-NoReparseTree $diagnostics)){throw 'Diagnostics output tree contains a reparse point.'}
New-Item -ItemType Directory -Path $diagnostics -Force | Out-Null
$files=@()
foreach($relative in @('b\CMakeCache.txt','b\CMakeFiles\CMakeConfigureLog.yaml','b\vcpkg-manifest-install.log','artifacts\package-tests.json','artifacts\pe-dependencies.json')){
    $path=Join-Path $Workspace $relative
    if((Test-SafeWorkspacePath $path) -and (Test-Path -LiteralPath $path -PathType Leaf)){$files+=Get-Item -LiteralPath $path}
}
$logs=Join-Path $Workspace 'logs'
if((Test-SafeWorkspacePath $logs) -and (Test-Path -LiteralPath $logs)){$files+=Get-ChildItem -LiteralPath $logs -File}
$buildtrees=Join-Path $Workspace 'vcpkg\buildtrees'
if((Test-SafeWorkspacePath $buildtrees) -and (Test-Path -LiteralPath $buildtrees)){
    # Only each port's top-level logs; never descend into src/reparsepoints.
    foreach($port in Get-ChildItem $buildtrees -Directory | Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0}){
        $files+=Get-ChildItem -LiteralPath $port.FullName -File -Filter '*.log'
    }
}
foreach($file in $files){
    if(-not (Test-SafeWorkspacePath $file.FullName)){continue}
    $relative=[IO.Path]::GetRelativePath($Workspace,$file.FullName)
    $target=Join-Path $diagnostics $relative
    if(-not (Test-SafeWorkspacePath $target)){continue}
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
}
$dist=Join-Path $Workspace 'dist'
if((Test-SafeWorkspacePath (Join-Path $dist 'bin\LichtFeld-Studio.exe')) -and (Test-Path -LiteralPath (Join-Path $dist 'bin\LichtFeld-Studio.exe')) -and (Test-NoReparseTree $dist)){
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

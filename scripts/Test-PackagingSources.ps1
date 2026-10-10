[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$scripts=Get-ChildItem (Join-Path $repo 'scripts') -Filter '*.ps1' -File
foreach ($file in $scripts) {
    $tokens=$null; $errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw (($errors | ForEach-Object {$_.ToString()}) -join "`n") }
    Write-Host "PowerShell parser PASS: $($file.Name)"
}
$lock=Get-Content (Join-Path $repo 'upstream.lock.json') -Raw | ConvertFrom-Json
if ($lock.commit -ne '09d338189162b52d888fdbe2c88025e31d0dea05' -or $lock.tag -ne 'v0.5.4') { throw 'Unexpected source pin.' }
$buildScript=Get-Content (Join-Path $PSScriptRoot 'Build-Portable.ps1') -Raw
if (-not $buildScript.Contains($lock.commit) -or -not $buildScript.Contains($lock.vcpkgCommit)) { throw 'Build script and lock disagree.' }
foreach ($name in @('README.md','LICENSE','docs/INSTALLATIE-NL.md','docs/LICENTIES.md','docs/FOTO-VIDEO-IMPORT.md','docs/GPU-TESTPROTOCOL.md','patches/portable-paths.patch')) {
    if (-not (Test-Path (Join-Path $repo $name))) { throw "Packaging source ontbreekt: $name" }
}
$workflow=Get-Content (Join-Path $repo '.github\workflows\portable-windows.yml') -Raw
foreach ($match in [regex]::Matches($workflow,'(?m)^\s+uses:\s+([^\s#]+)')) {
    if ($match.Groups[1].Value -notmatch '^actions/[a-z-]+(?:/(?:restore|save))?@[a-f0-9]{40}$') { throw 'Action must use an exact official commit.' }
}
if ($workflow -notmatch 'runs-on: windows-2022') { throw 'Expected pinned Windows runner image family.' }
Write-Host 'Packaging pin, required sources and Actions commit checks PASS.'

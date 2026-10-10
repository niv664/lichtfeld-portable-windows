[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Workspace,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Workspace=[IO.Path]::GetFullPath($Workspace)
if (-not $OutputDirectory) { $OutputDirectory=Join-Path $Workspace 'artifacts' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory=(Resolve-Path $OutputDirectory).Path
$lock=Get-Content (Join-Path $repo 'upstream.lock.json') -Raw | ConvertFrom-Json
$source=Join-Path $Workspace 'src'; $build=Join-Path $Workspace 'b'; $dist=Join-Path $Workspace 'dist'
if (-not (Test-Path (Join-Path $dist 'bin\LichtFeld-Studio.exe'))) { throw 'Voer eerst Build-Portable.ps1 -Stage Install uit.' }
$actual=(& git -C $source rev-parse HEAD).Trim()
if ($actual -ne $lock.commit) { throw "Onverwachte broncommit: $actual" }
Copy-Item (Join-Path $source 'src\python\lfs_splat_lod_hierarchy.py') (Join-Path $dist 'bin') -Force
Copy-Item (Join-Path $source 'THIRD_PARTY_LICENSES.md') $dist -Force
Copy-Item (Join-Path $repo 'docs\INSTALLATIE-NL.md') (Join-Path $dist 'README-NL.md') -Force
Copy-Item (Join-Path $repo 'docs\LICENTIES.md'),(Join-Path $repo 'docs\FOTO-VIDEO-IMPORT.md'),(Join-Path $repo 'docs\GPU-TESTPROTOCOL.md') $dist -Force
New-Item -ItemType Directory -Path (Join-Path $dist 'scripts') -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'Test-TargetComputer.ps1'),(Join-Path $PSScriptRoot 'Test-PeDependencies.ps1') (Join-Path $dist 'scripts') -Force
Copy-Item (Join-Path $repo 'templates\Start-LichtFeld.cmd'),(Join-Path $repo 'templates\Controleer-computer.cmd') $dist -Force
$licenses=Join-Path $dist 'licenses'
New-Item -ItemType Directory -Path $licenses -Force | Out-Null
# Include actual license files from the exact installed dependency graph.
$share=Join-Path $build 'vcpkg_installed\x64-windows\share'
foreach ($port in Get-ChildItem $share -Directory) {
    $copyright=Join-Path $port.FullName 'copyright'
    if (Test-Path $copyright) {
        $target=Join-Path $licenses ('vcpkg\'+$port.Name)
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Copy-Item $copyright $target
    }
}
$licenseRoots=@((Join-Path $source 'external'),(Join-Path $build '_deps'),(Join-Path $source 'resources\licenses'),(Join-Path $source 'src'))
foreach ($licenseRoot in $licenseRoots) {
    if (-not (Test-Path $licenseRoot)) { continue }
    foreach ($file in Get-ChildItem $licenseRoot -File -Recurse | Where-Object { $_.Name -match '(?i)(^|[._-])(licen[sc]e|copying|notice|copyright|ofl|patents)($|[._-])' -and $_.FullName -notmatch '[\\/](\.git|CMakeFiles)[\\/]' }) {
        $relative=[IO.Path]::GetRelativePath($licenseRoot,$file.FullName)
        $target=Join-Path $licenses ((Split-Path $licenseRoot -Leaf)+'\'+$relative)
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item $file.FullName $target -Force
    }
}
# uv release archives do not include notices; obtain the exact upstream texts.
$uvLicenses=Join-Path $licenses 'uv'
New-Item -ItemType Directory -Path $uvLicenses -Force | Out-Null
foreach ($name in @('LICENSE-MIT','LICENSE-APACHE')) {
    Invoke-WebRequest ('https://raw.githubusercontent.com/astral-sh/uv/0.10.2/'+$name) -OutFile (Join-Path $uvLicenses $name)
}
$cudaEula=Join-Path $env:CUDA_PATH 'EULA.txt'
$cudaLicenses=Join-Path $licenses 'NVIDIA-CUDA-12.8.0'
New-Item -ItemType Directory -Path $cudaLicenses -Force | Out-Null
if (Test-Path $cudaEula) { Copy-Item $cudaEula $cudaLicenses }
else { Invoke-WebRequest 'https://docs.nvidia.com/cuda/archive/12.8.0/eula/index.html' -OutFile (Join-Path $cudaLicenses 'EULA.html') }
foreach ($file in Get-ChildItem $env:CUDA_PATH -File | Where-Object {$_.Name -match 'acknowledg|license|notice'}) { Copy-Item $file.FullName $cudaLicenses -Force }
# The CMake install normally supplies app-local MSVC runtimes. Add only REDIST,
# never compiler DLLs, and never copy Windows system or NVIDIA driver files.
if ($env:VCToolsRedistDir) {
    $crt=Join-Path $env:VCToolsRedistDir 'x64\Microsoft.VC143.CRT'
    if (Test-Path $crt) { Copy-Item (Join-Path $crt '*.dll') (Join-Path $dist 'bin') -Force }
}
$sourceName='LichtFeld-Studio-v0.5.4-corresponding-source.tar.gz'
$packageName='LichtFeld-Studio-v0.5.4-portable-windows-x64'
$manifest=[ordered]@{version='0.5.4';upstreamCommit=$actual;vcpkgCommit=$lock.vcpkgCommit;cuda='12.8.0';minimumDriverWindows=$lock.minimumDriverPolicyWindows;minimumComputeCapability='7.5';builtAtUtc=[DateTime]::UtcNow.ToString('o');sourceArchive=$sourceName;packagingCommit=(& git -C $repo rev-parse HEAD).Trim();gpuValidation='not run in GitHub Actions';binarySigning='unsigned'}
$manifest | ConvertTo-Json | Set-Content (Join-Path $dist 'BUILD-MANIFEST.json') -Encoding utf8
$inventory=Get-ChildItem $dist -Recurse -File | Where-Object {$_.Extension -in @('.exe','.dll','.pyd')} | Sort-Object FullName | ForEach-Object {
    $version=[Diagnostics.FileVersionInfo]::GetVersionInfo($_.FullName)
    [pscustomobject]@{path=[IO.Path]::GetRelativePath($dist,$_.FullName).Replace('\','/');fileVersion=$version.FileVersion;publisher=$version.CompanyName;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$inventory | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dist 'DEPENDENCY-INVENTORY.json') -Encoding utf8
Copy-Item (Join-Path $build 'vcpkg_installed\vcpkg\status') (Join-Path $dist 'VCPKG-INSTALLED-STATUS.txt')
$sourceIndex=@(
    'Exact corresponding sources for the adjacent binary package.',
    'upstream/: GPLv3 app and recursive external/libvterm submodule, with the portable patch applied.',
    'packaging/: build/install/package/test scripts, lock file, portable patch, and documentation.',
    'vcpkg/: exact tool/registry scripts and patches; source-archives/: fetched original dependency archives.',
    'fetchcontent/: fetched dependency source trees used by CMake.',
    'CUDA, Windows and Microsoft redistributables retain their separate vendor terms; proprietary SDK sources are not included.'
)
$sourceBundle=Join-Path $Workspace 'source-bundle'
if (Test-Path $sourceBundle) { throw "Bronbundel bestaat al: gebruik een schone aparte Workspace ($sourceBundle)." }
New-Item -ItemType Directory -Path $sourceBundle | Out-Null
$sourceIndex | Set-Content (Join-Path $sourceBundle 'README.txt') -Encoding utf8
function Copy-SourceTree([string]$From,[string]$To) {
    New-Item -ItemType Directory -Path $To -Force | Out-Null
    # Robocopy uses native literal paths. Return codes 0..7 indicate success.
    # Rooted exclusions preserve legitimate nested source directories such as tools/build.
    $excludedRoots=@('artifacts','work','logs','buildtrees','packages','downloads') | ForEach-Object {Join-Path $From $_}
    & robocopy $From $To /E /XD .git __pycache__ @excludedRoots /XF .git '*.obj' '*.o' '*.pdb' '*.pyc' /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Kopieren bronboom mislukt: $From ($LASTEXITCODE)" }
}
Copy-SourceTree $source (Join-Path $sourceBundle 'upstream')
Copy-SourceTree $repo (Join-Path $sourceBundle 'packaging')
Copy-SourceTree (Join-Path $Workspace 'vcpkg') (Join-Path $sourceBundle 'vcpkg')
$usedPorts=Join-Path $Workspace 'vcpkg\buildtrees\versioning_\versions'
if (-not (Test-Path $usedPorts)) { throw 'Exact gebruikte historische vcpkg-portrecipes ontbreken.' }
Copy-SourceTree $usedPorts (Join-Path $sourceBundle 'used-versioned-port-recipes')
& git -C (Join-Path $Workspace 'vcpkg') show ($lock.vcpkgBuiltinBaseline+':versions/baseline.json') | Set-Content (Join-Path $sourceBundle 'vcpkg-original-baseline.json') -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw 'De gebruikte vcpkg-baseline kon niet worden gearchiveerd.' }
$archiveDir=Join-Path $sourceBundle 'source-archives'
New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
foreach ($file in Get-ChildItem (Join-Path $Workspace 'downloads\vcpkg') -File | Where-Object {$_.Name -match '\.(zip|tar|gz|bz2|xz|tgz|7z)$'}) { Copy-Item $file.FullName $archiveDir }
foreach ($port in Get-ChildItem (Join-Path $Workspace 'vcpkg\buildtrees') -Directory) {
    $portSource=Join-Path $port.FullName 'src'
    if (Test-Path $portSource) { Copy-SourceTree $portSource (Join-Path $sourceBundle ('patched-port-sources\'+$port.Name)) }
}
foreach ($dep in Get-ChildItem (Join-Path $build '_deps') -Directory | Where-Object {$_.Name -like '*-src'}) { Copy-SourceTree $dep.FullName (Join-Path $sourceBundle ('fetchcontent\'+$dep.Name)) }
Copy-Item (Join-Path $build 'vcpkg_installed\vcpkg\status') (Join-Path $sourceBundle 'vcpkg-installed-status.txt')
& git -C $source diff --binary | Set-Content (Join-Path $sourceBundle 'applied-upstream.patch') -Encoding utf8
$sourceHashLines=Get-ChildItem $sourceBundle -Recurse -File | Sort-Object FullName | ForEach-Object { '{0} *{1}' -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(),[IO.Path]::GetRelativePath($sourceBundle,$_.FullName).Replace('\','/') }
$sourceHashLines | Set-Content (Join-Path $sourceBundle 'SHA256SUMS.txt') -Encoding ascii
& tar.exe -czf (Join-Path $OutputDirectory $sourceName) -C $Workspace source-bundle
if ($LASTEXITCODE -ne 0) { throw 'Bronarchief maken mislukt.' }
$hashLines=Get-ChildItem $dist -Recurse -File | Where-Object {$_.Name -ne 'SHA256SUMS.txt'} | Sort-Object FullName | ForEach-Object { '{0} *{1}' -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(),[IO.Path]::GetRelativePath($dist,$_.FullName).Replace('\','/') }
$hashLines | Set-Content (Join-Path $dist 'SHA256SUMS.txt') -Encoding ascii
& (Join-Path $PSScriptRoot 'Test-PortablePackage.ps1') -PackageRoot $dist -AllowMissingDriver -ReportPath (Join-Path $OutputDirectory 'package-tests.json')
if ($LASTEXITCODE -ne 0) { throw 'Portable pakketvalidatie faalde.' }
$zipRoot=Join-Path $Workspace $packageName
if (Test-Path $zipRoot) { throw 'ZIP-staging bestaat al; gebruik een nieuwe Workspace.' }
New-Item -ItemType Directory -Path $zipRoot | Out-Null
Copy-Item (Join-Path $dist '*') $zipRoot -Recurse
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath=Join-Path $OutputDirectory ($packageName+'.zip')
[IO.Compression.ZipFile]::CreateFromDirectory($zipRoot,$zipPath,[IO.Compression.CompressionLevel]::Optimal,$true)
foreach ($file in @($zipPath,(Join-Path $OutputDirectory $sourceName))) {
    '{0} *{1}' -f (Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant(),(Split-Path $file -Leaf) | Set-Content ($file+'.sha256') -Encoding ascii
}
Get-ChildItem $OutputDirectory | Select-Object Name,Length

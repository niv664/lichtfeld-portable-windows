#requires -Version 7.0
<#
.SYNOPSIS
Builds the pinned LichtFeld Studio Windows x64 portable distribution.
.DESCRIPTION
Run on a build computer with VS 2022 C++ and Clang, CMake >= 3.30, Ninja,
Git and CUDA Toolkit 12.8.0. This script installs no system software.
Stage Configure prepares the pinned source and vcpkg and configures CMake;
Build compiles it; Install runs the upstream portable installation.
The resulting dist directory is input for New-PortablePackage.ps1.
.EXAMPLE
pwsh -File .\scripts\Build-Portable.ps1 -Workspace C:\lfp -Stage All -Jobs 2
#>
[CmdletBinding()]
param(
    [ValidateSet('Configure', 'Build', 'Install', 'All')]
    [string]$Stage = 'All',
    [string]$Workspace,
    [ValidateRange(1, 16)]
    [int]$Jobs = 2,
    [ValidateRange(1, 16)]
    [int]$VcpkgJobs = 2,
    [string]$VsInstallationPath,
    [string]$CudaPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Native exit codes are checked explicitly, including the reversible patch check.
$PSNativeCommandUseErrorActionPreference = $false

$UpstreamRepository = 'https://github.com/MrNeRF/LichtFeld-Studio.git'
$UpstreamTag = 'v0.5.4'
$UpstreamCommit = '09d338189162b52d888fdbe2c88025e31d0dea05'
$VcpkgRepository = 'https://github.com/microsoft/vcpkg.git'
# The tool checkout must include shader-slang 2026.5; the application's older
# builtin-baseline selects package versions and is deliberately unchanged.
$VcpkgCommit = 'e456309491fd875487bf02b8a0dca76c1b1b00cc'
$VcpkgBaseline = 'c3867e714dd3a51c272826eea77267876517ed99'
$PackagingRoot = Split-Path -Parent $PSScriptRoot
$PatchPath = Join-Path $PackagingRoot 'patches\portable-paths.patch'
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = Join-Path (Split-Path -Parent $PackagingRoot) 'work\lfp'
}
$Workspace = [IO.Path]::GetFullPath($Workspace)
$SourceDir = Join-Path $Workspace 'src'
$VcpkgDir = Join-Path $Workspace 'vcpkg'
$BuildDir = Join-Path $Workspace 'b'
$DistDir = Join-Path $Workspace 'dist'
$LogDir = Join-Path $Workspace 'logs'

function Invoke-CheckedNative {
    param([Parameter(Mandatory)][string]$Program, [string[]]$Arguments = @())
    Write-Host ('> {0} {1}' -f $Program, ($Arguments -join ' '))
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Program failed with exit code $LASTEXITCODE. See the transcript in $LogDir."
    }
}

function Get-CheckedNativeOutput {
    param([Parameter(Mandatory)][string]$Program, [string[]]$Arguments = @())
    $result = @(& $Program @Arguments)
    if ($LASTEXITCODE -ne 0) {
        throw "$Program failed with exit code $LASTEXITCODE."
    }
    return (($result | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function Assert-PinnedCheckout {
    param([string]$Path, [string]$Repository, [string]$Commit)
    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) {
        throw "Expected Git checkout is missing: $Path. Run -Stage Configure first."
    }
    $origin = Get-CheckedNativeOutput git @('-C', $Path, 'remote', 'get-url', 'origin')
    if ($origin.TrimEnd('/') -ne $Repository.TrimEnd('/')) {
        throw "Unexpected repository at $Path ($origin). Use a dedicated empty workspace."
    }
    $actual = Get-CheckedNativeOutput git @('-C', $Path, 'rev-parse', 'HEAD')
    if ($actual -ne $Commit) {
        throw "Unexpected commit at $Path ($actual); expected $Commit. Use a dedicated empty workspace."
    }
}

function Initialize-PinnedCheckout {
    param([string]$Path, [string]$Repository, [string]$Commit, [switch]$FullClone)
    if (-not (Test-Path -LiteralPath $Path)) {
        # vcpkg materializes historical port trees under a controlled Git
        # environment. Lazy promisor fetches can fail there, so retain the full
        # pinned repository history for dependency registry reads.
        $cloneArguments = @('clone', '--no-checkout')
        if (-not $FullClone) { $cloneArguments += '--filter=blob:none' }
        $cloneArguments += @($Repository, $Path)
        Invoke-CheckedNative git $cloneArguments
        Invoke-CheckedNative git @('-C', $Path, 'checkout', '--detach', $Commit)
    }
    Assert-PinnedCheckout $Path $Repository $Commit
    if ($FullClone) {
        $partialFilter = @(& git -C $Path config --get remote.origin.partialclonefilter)
        if ($partialFilter.Count -gt 0) {
            throw 'vcpkg vereist een volledige Git-clone; gebruik een nieuwe lege Workspace met dit bouwscript.'
        }
    }
}

function Assert-PortablePatch {
    if (-not (Test-Path -LiteralPath $PatchPath)) {
        throw "Required source patch is missing: $PatchPath"
    }
    & git -C $SourceDir apply --reverse --check $PatchPath 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'The checkout does not contain the exact portable-paths.patch. Run -Stage Configure first.'
    }
    $changedFiles = @(& git -C $SourceDir diff --name-only)
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect upstream source changes.' }
    $unexpected = @($changedFiles | Where-Object { $_ -notin @('CMakeLists.txt', 'src/python/CMakeLists.txt') })
    if ($unexpected.Count -gt 0) {
        throw "Unexpected source changes: $($unexpected -join ', '). Use a dedicated workspace."
    }
    $actualPatch = Get-CheckedNativeOutput git @('-C', $SourceDir, '-c', 'core.abbrev=8', 'diff', '--no-color', '--no-ext-diff', '--', 'CMakeLists.txt', 'src/python/CMakeLists.txt')
    $expectedPatch = (Get-Content -LiteralPath $PatchPath -Raw).Replace("`r`n", "`n").Trim()
    if ($actualPatch.Replace("`r`n", "`n").Trim() -ne $expectedPatch) {
        throw 'The upstream source contains changes beyond the recorded portable patch.'
    }
    Invoke-CheckedNative git @('-C', $SourceDir, 'diff', '--check')
}

function Assert-PinnedSubmodules {
    $status = Get-CheckedNativeOutput git @('-C', $SourceDir, 'submodule', 'status', '--recursive')
    if ($status -match '(?m)^[-+U]') {
        throw 'One or more upstream submodules are missing, modified or at the wrong revision.'
    }
    return $status
}

function Initialize-BuildEnvironment {
    if (-not $IsWindows -or -not [Environment]::Is64BitProcess) {
        throw 'Run this script with 64-bit PowerShell 7 on Windows.'
    }
    foreach ($tool in @('git', 'cmake', 'ninja')) {
        if (-not (Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue)) {
            throw "Required build tool is missing from PATH: $tool"
        }
    }
    $cmakeVersionText = Get-CheckedNativeOutput cmake @('--version')
    if ($cmakeVersionText -notmatch 'cmake version (\d+\.\d+\.\d+)') {
        throw 'Could not determine the CMake version.'
    }
    if ([version]$Matches[1] -lt [version]'3.30.0') {
        throw 'LichtFeld Studio requires CMake 3.30 or newer.'
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if ([string]::IsNullOrWhiteSpace($script:VsInstallationPath)) {
        if (-not (Test-Path -LiteralPath $vswhere)) {
            throw 'vswhere.exe is missing. Install the official VS 2022 C++ build tools first.'
        }
        $script:VsInstallationPath = Get-CheckedNativeOutput $vswhere @(
            '-latest', '-products', '*', '-version', '[17.10,18.0)',
            '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
            '-property', 'installationPath'
        )
        if ([string]::IsNullOrWhiteSpace($script:VsInstallationPath)) {
            throw 'Visual Studio 2022 >= 17.10 with the desktop C++ workload is required.'
        }
    }
    $launch = Join-Path $script:VsInstallationPath 'Common7\Tools\Launch-VsDevShell.ps1'
    if (-not (Test-Path -LiteralPath $launch)) {
        throw "Visual Studio developer shell is missing: $launch"
    }
    & $launch -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
    if ($env:VisualStudioVersion -ne '17.0') {
        throw "Expected a Visual Studio 2022 developer shell; got '$env:VisualStudioVersion'."
    }
    if (-not (Get-Command cl.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'The Visual Studio x64 developer shell did not expose cl.exe.'
    }
    if ($env:VSCMD_ARG_TGT_ARCH -ne 'x64') {
        throw "Expected x64 MSVC target, got '$env:VSCMD_ARG_TGT_ARCH'."
    }
    $clang = Join-Path $script:VsInstallationPath 'VC\Tools\Llvm\x64\bin\clang-cl.exe'
    if (-not (Test-Path -LiteralPath $clang)) {
        throw 'Install the VS individual component C++ Clang Compiler for Windows (Microsoft.VisualStudio.Component.VC.Llvm.Clang).'
    }
    # Keep MSVC first. The libplacebo port discovers clang-cl via VSINSTALLDIR;
    # prepending LLVM also exposes clang++ and changes CMake's default compiler.
    if ([string]::IsNullOrWhiteSpace($script:CudaPath)) {
        $script:CudaPath = Join-Path $env:ProgramFiles 'NVIDIA GPU Computing Toolkit\CUDA\v12.8'
    }
    $script:CudaPath = [IO.Path]::GetFullPath($script:CudaPath)
    $nvcc = Join-Path $script:CudaPath 'bin\nvcc.exe'
    if (-not (Test-Path -LiteralPath $nvcc)) {
        throw "CUDA Toolkit 12.8.0 nvcc.exe is missing: $nvcc. Install the official toolkit on the build computer."
    }
    $cudaVersionFile = Join-Path $script:CudaPath 'version.json'
    if (-not (Test-Path -LiteralPath $cudaVersionFile)) {
        throw "Cannot verify the toolkit release: $cudaVersionFile is missing."
    }
    $cudaVersion = Get-Content -LiteralPath $cudaVersionFile -Raw | ConvertFrom-Json
    if ($cudaVersion.cuda.version -notmatch '^12\.8\.0(?:\.|$)') {
        throw "This recipe pins CUDA Toolkit 12.8.0; found '$($cudaVersion.cuda.version)'."
    }
    $nvccVersionText = Get-CheckedNativeOutput $nvcc @('--version')
    if ($nvccVersionText -notmatch 'release 12\.8,') {
        throw 'The CUDA compiler is not release 12.8.'
    }
    $env:CUDA_PATH = $script:CudaPath
    $env:CUDA_PATH_V12_8 = $script:CudaPath
    $env:PATH = (Join-Path $script:CudaPath 'bin') + [IO.Path]::PathSeparator + $env:PATH
    $env:VCPKG_ROOT = $VcpkgDir
    $env:VCPKG_DEFAULT_TRIPLET = 'x64-windows'
    $env:VCPKG_MAX_CONCURRENCY = [string]$VcpkgJobs
    $env:CMAKE_BUILD_PARALLEL_LEVEL = [string]$Jobs
    # vcpkg's own hash-verified download cache; never share installed package dirs.
    $env:VCPKG_DOWNLOADS = Join-Path $Workspace 'downloads\vcpkg'
    New-Item -ItemType Directory -Force -Path $env:VCPKG_DOWNLOADS | Out-Null
    $compiler = Get-Command cl.exe -CommandType Application
    $script:BuildEnvironment = [ordered]@{
        upstream_repository = $UpstreamRepository
        upstream_tag = $UpstreamTag
        upstream_commit = $UpstreamCommit
        vcpkg_repository = $VcpkgRepository
        vcpkg_tool_commit = $VcpkgCommit
        vcpkg_builtin_baseline = $VcpkgBaseline
        cuda_toolkit = $cudaVersion.cuda.version
        cuda_compiler_version = $nvccVersionText
        cmake_version = $cmakeVersionText
        ninja_version = Get-CheckedNativeOutput ninja @('--version')
        visual_studio = $script:VsInstallationPath
        msvc_compiler = $compiler.Source
        msvc_file_version = (Get-Item -LiteralPath $compiler.Source).VersionInfo.FileVersion
        clang_version = Get-CheckedNativeOutput $clang @('--version')
        jobs = $Jobs
        vcpkg_jobs = $VcpkgJobs
        source_directory = $SourceDir
        build_directory = $BuildDir
        install_directory = $DistDir
        patch_sha256 = (Get-FileHash -LiteralPath $PatchPath -Algorithm SHA256).Hash.ToLowerInvariant()
        recorded_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
    }
    $script:BuildEnvironment | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $LogDir 'build-environment.json') -Encoding utf8NoBOM
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$transcript = Join-Path $LogDir ("{0}-{1}.log" -f $Stage.ToLowerInvariant(), [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
$transcriptStarted = $false
try {
    Start-Transcript -LiteralPath $transcript | Out-Null
    $transcriptStarted = $true
    Write-Host "LichtFeld Studio $UpstreamTag ($UpstreamCommit); stage $Stage"
    Write-Host "Workspace: $Workspace"
    if ($Workspace.Length -gt 100) {
        Write-Warning 'Use a shorter -Workspace path if a dependency reports Windows path-length errors.'
    }
    Initialize-BuildEnvironment
    if ($Stage -in @('Configure', 'All')) {
        Initialize-PinnedCheckout $SourceDir $UpstreamRepository $UpstreamCommit
        Invoke-CheckedNative git @('-C', $SourceDir, 'submodule', 'sync', '--recursive')
        Invoke-CheckedNative git @('-C', $SourceDir, 'submodule', 'update', '--init', '--recursive')
        $submoduleStatus = Assert-PinnedSubmodules
        $manifest = Get-Content -LiteralPath (Join-Path $SourceDir 'vcpkg.json') -Raw | ConvertFrom-Json
        if ($manifest.'builtin-baseline' -ne $VcpkgBaseline) {
            throw 'The upstream vcpkg baseline differs from this pinned build recipe.'
        }
        & git -C $SourceDir apply --reverse --check $PatchPath 2>$null
        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedNative git @('-C', $SourceDir, 'apply', '--check', $PatchPath)
            Invoke-CheckedNative git @('-C', $SourceDir, 'apply', $PatchPath)
        }
        Assert-PortablePatch
        Initialize-PinnedCheckout $VcpkgDir $VcpkgRepository $VcpkgCommit -FullClone
        if (-not (Test-Path -LiteralPath (Join-Path $VcpkgDir 'vcpkg.exe'))) {
            Invoke-CheckedNative (Join-Path $VcpkgDir 'bootstrap-vcpkg.bat') @('-disableMetrics')
        }
        Push-Location $SourceDir
        try {
            Invoke-CheckedNative cmake @(
                '--preset', 'windows-release', '-B', $BuildDir,
                '-DBUILD_PORTABLE=ON', '-DBUILD_PYTHON_STUBS=OFF',
                '-DBUILD_CUDA_MIN_SM=75', '-DBUILD_TESTS=OFF',
                '-DBUILD_FORMAT_TESTS=OFF', '-DBUILD_UNICODE_TEST_ONLY=OFF',
                '-DBUILD_VISUALIZER_TESTS=OFF', '-DBUILD_PANEL_LAYOUT_TESTS=OFF',
                '-DLFS_DEV_IMPORT_SOURCE_PYTHON=OFF', '-DLFS_DEV_IMPORT_SOURCE_RESOURCES=OFF',
                '-DLFS_ENABLE_CUDA_DEVICE_DEBUG=OFF', '-DLFS_ENABLE_VULKAN_VALIDATION=OFF',
                "-DLFS_VCPKG_MAX_CONCURRENCY=$VcpkgJobs",
                "-DCMAKE_CUDA_COMPILER=$(Join-Path $CudaPath 'bin\nvcc.exe')",
                "-DCMAKE_C_COMPILER=$($script:BuildEnvironment.msvc_compiler)",
                "-DCMAKE_CXX_COMPILER=$($script:BuildEnvironment.msvc_compiler)",
                "-DCMAKE_CUDA_HOST_COMPILER=$($script:BuildEnvironment.msvc_compiler)",
                "-DLFS_DOWNLOAD_CACHE_DIR=$(Join-Path $Workspace 'downloads\upstream')"
            )
        } finally { Pop-Location }
        $submoduleStatus | Set-Content -LiteralPath (Join-Path $LogDir 'upstream-submodules.txt') -Encoding utf8NoBOM
    }
    if ($Stage -in @('Build', 'Install', 'All')) {
        Assert-PinnedCheckout $SourceDir $UpstreamRepository $UpstreamCommit
        Assert-PinnedCheckout $VcpkgDir $VcpkgRepository $VcpkgCommit
        Assert-PortablePatch
        $null = Assert-PinnedSubmodules
        if (-not (Test-Path -LiteralPath (Join-Path $BuildDir 'CMakeCache.txt'))) {
            throw 'The configured CMake build directory is missing. Run -Stage Configure first.'
        }
    }
    if ($Stage -in @('Build', 'All')) {
        Invoke-CheckedNative cmake @('--build', $BuildDir, '--config', 'Release', '--parallel', [string]$Jobs)
        if (-not (Test-Path -LiteralPath (Join-Path $BuildDir 'LichtFeld-Studio.exe'))) {
            throw 'The build reported success but LichtFeld-Studio.exe is missing.'
        }
    }
    if ($Stage -in @('Install', 'All')) {
        Invoke-CheckedNative cmake @('--install', $BuildDir, '--config', 'Release', '--prefix', $DistDir)
        if (-not (Test-Path -LiteralPath (Join-Path $DistDir 'bin\LichtFeld-Studio.exe'))) {
            throw 'The portable installation did not produce bin\LichtFeld-Studio.exe.'
        }
    }
    Write-Host "Stage $Stage succeeded. Install directory: $DistDir"
} finally {
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
}

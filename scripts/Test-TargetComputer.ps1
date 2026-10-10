#Requires -Version 5.1
<#
.SYNOPSIS
Controleert een uitgepakt LichtFeld-pakket en de NVIDIA-driver zonder installatie.
.DESCRIPTION
Gebruik de gewone 64-bit Windows PowerShell 5.1. Er zijn geen administratorrechten,
Visual Studio, Git, Python-ontwikkelomgeving of CUDA Toolkit nodig. De controle
leest bestanden en de geinstalleerde CUDA-driver; alleen het JSON-rapport en
eventuele .NET-compilatiebestanden worden in de tijdelijke gebruikersmap geschreven.
Er wordt geen applicatie gestart, GPU-kernel uitgevoerd of project getraind.
.EXAMPLE
.\scripts\Test-TargetComputer.ps1 -PackageRoot C:\Users\naam\LichtFeld
#>
[CmdletBinding()]
param(
    [string]$PackageRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$JsonOutputPath = (Join-Path ([IO.Path]::GetTempPath()) ('LichtFeld-target-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))),
    [string[]]$AdditionalSearchDirectory = @('bin', 'DLLs', 'extensions')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$minimumDriver = [version]'571.96'
$recommendedDriver = [version]'572.61'
$sourceGa = 'https://docs.nvidia.com/cuda/archive/12.8.0/cuda-toolkit-release-notes/index.html'
$sourceUpdate = 'https://docs.nvidia.com/cuda/archive/12.8.1/cuda-toolkit-release-notes/index.html'
$checks = New-Object 'System.Collections.Generic.List[object]'
$gpuResults = @()

function Add-Check([string]$Name, [string]$Status, [string]$Detail) {
    $checks.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail })
    $color = 'Gray'
    if ($Status -eq 'PASS') { $color = 'Green' }
    elseif ($Status -eq 'FAIL') { $color = 'Red' }
    elseif ($Status -eq 'WARN') { $color = 'Yellow' }
    Write-Host ("[{0}] {1}: {2}" -f $Status, $Name, $Detail) -ForegroundColor $color
}

Write-Host 'LichtFeld Studio - controle doelcomputer (alleen lezen)'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
$jsonPath = [IO.Path]::GetFullPath($JsonOutputPath)
if (-not $jsonPath.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'JsonOutputPath moet in de tijdelijke gebruikersmap liggen. Er worden geen systeembestanden gewijzigd.'
}
if (-not (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($jsonPath)) -PathType Container)) {
    throw 'De map voor het JSON-rapport bestaat niet.'
}

$isWindowsPlatform = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
$nativeArchitecture = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) { $nativeArchitecture = $env:PROCESSOR_ARCHITEW6432 }
if ($isWindowsPlatform -and [Environment]::Is64BitOperatingSystem -and $nativeArchitecture -eq 'AMD64') {
    Add-Check 'Windows x64' 'PASS' ("Windows kernel {0}; AMD64." -f [Environment]::OSVersion.Version)
} else { Add-Check 'Windows x64' 'FAIL' 'Dit pakket vereist Windows op een AMD64/x64-computer.' }
if ([Environment]::Is64BitProcess) { Add-Check 'PowerShell x64' 'PASS' '64-bit proces.' }
else { Add-Check 'PowerShell x64' 'FAIL' 'Open de 64-bit Windows PowerShell en voer de controle opnieuw uit.' }

$root = [IO.Path]::GetFullPath($PackageRoot).TrimEnd([char[]]'\/')
$rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
$packageExists = Test-Path -LiteralPath $root -PathType Container
if ($packageExists) {
    Add-Check 'Pakketmap' 'PASS' $root
    $application = Join-Path $root 'bin\LichtFeld-Studio.exe'
    if (Test-Path -LiteralPath $application -PathType Leaf) { Add-Check 'Applicatie' 'PASS' 'bin\LichtFeld-Studio.exe aanwezig.' }
    else { Add-Check 'Applicatie' 'FAIL' 'bin\LichtFeld-Studio.exe ontbreekt; een start-wrapper alleen is geen applicatiebuild.' }

    $manifest = Join-Path $root 'SHA256SUMS.txt'
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        $hashErrors = New-Object 'System.Collections.Generic.List[string]'
        $listed = @{}
        $hashCount = 0
        $lineNumber = 0
        foreach ($line in [IO.File]::ReadAllLines($manifest)) {
            $lineNumber++
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
            if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
                $hashErrors.Add("Ongeldige manifestregel $lineNumber.")
                continue
            }
            $expectedHash = $Matches[1]
            $relative = $Matches[2]
            if ([IO.Path]::IsPathRooted($relative)) { $hashErrors.Add("Absoluut pad in manifestregel $lineNumber."); continue }
            try {
                $candidate = [IO.Path]::GetFullPath((Join-Path $root $relative))
                if (-not $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    $hashErrors.Add("Pad verlaat pakket in manifestregel $lineNumber.")
                    continue
                }
                if ($listed.ContainsKey($candidate)) { $hashErrors.Add("Dubbel bestand in manifest: $relative."); continue }
                $listed[$candidate] = $true
                if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { $hashErrors.Add("Ontbreekt: $relative."); continue }
                $actual = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
                $hashCount++
                if ($actual -ne $expectedHash) { $hashErrors.Add("SHA-256 wijkt af: $relative.") }
            } catch { $hashErrors.Add("Kan manifestbestand niet controleren: $relative. $($_.Exception.Message)") }
        }
        if ($hashCount -eq 0) { $hashErrors.Add('Het manifest bevat geen gecontroleerde bestanden.') }
        foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
            if ($file.FullName -ne $manifest -and -not $listed.ContainsKey($file.FullName)) {
                $hashErrors.Add("Niet opgenomen in SHA-256-manifest: $($file.FullName.Substring($rootPrefix.Length)).")
            }
        }
        if ($hashErrors.Count -eq 0) { Add-Check 'SHA-256-manifest' 'PASS' "$hashCount bestanden gecontroleerd; alle hashes kloppen." }
        else { Add-Check 'SHA-256-manifest' 'FAIL' ($hashErrors.ToArray() -join ' ') }
    } else { Add-Check 'SHA-256-manifest' 'WARN' 'SHA256SUMS.txt ontbreekt; pakketintegriteit niet geverifieerd.' }
} else { Add-Check 'Pakketmap' 'FAIL' "Map bestaat niet: $root." }

$cudaPath = Join-Path ([Environment]::GetFolderPath('System')) 'nvcuda.dll'
$driverVersion = $null
$cudaApiVersion = $null
if (-not (Test-Path -LiteralPath $cudaPath -PathType Leaf)) {
    Add-Check 'NVIDIA-driver' 'FAIL' "nvcuda.dll ontbreekt in Windows System32. Laat IT een geschikte NVIDIA-driver installeren."
} else {
    Add-Check 'NVIDIA-driver DLL' 'PASS' $cudaPath
    $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($cudaPath)
    if ($versionInfo.CompanyName -notmatch 'NVIDIA') { Add-Check 'Driverherkomst' 'FAIL' 'nvcuda.dll meldt geen NVIDIA als producent.' }
    else { Add-Check 'Driverherkomst' 'PASS' $versionInfo.CompanyName }
    # NVIDIA Windows 32.0.15.7196 -> 571.96; gebruik numerieke versievelden.
    $driverNumber = ($versionInfo.FileBuildPart % 10) * 10000 + $versionInfo.FilePrivatePart
    if ($driverNumber -ge 10000 -and $versionInfo.FilePrivatePart -lt 10000) {
        $driverVersion = [version]('{0}.{1:D2}' -f [int][Math]::Floor($driverNumber / 100), ($driverNumber % 100))
        if ($driverVersion -lt $minimumDriver) {
            Add-Check 'Driverversie' 'FAIL' "Driver $driverVersion; dit gepinde CUDA 12.8.0-pakket vereist >=$minimumDriver. Nieuwere GPU-modellen kunnen een hogere driver vereisen."
        } else {
            Add-Check 'Driverversie' 'PASS' "Driver $driverVersion; pakketgrens >=$minimumDriver."
            if ($driverVersion -lt $recommendedDriver) { Add-Check 'Driveradvies' 'WARN' "Bij voorkeur >=$recommendedDriver (CUDA 12.8 Update 1/2). Laat IT alleen een driver installeren die de GPU ondersteunt." }
        }
    } else { Add-Check 'Driverversie' 'FAIL' "NVIDIA-versie kon niet betrouwbaar uit $($versionInfo.FileVersion) worden bepaald." }

    if ($isWindowsPlatform -and [Environment]::Is64BitProcess) {
        try {
            if (-not ('LichtFeldPortable.CudaDriverProbe' -as [type])) {
                # Add-Type gebruikt standaard Windows PowerShell/.NET; geen SDK/VS nodig.
                Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
namespace LichtFeldPortable {
    public sealed class DeviceInfo {
        public int Index; public string Name; public int Major; public int Minor; public ulong MemoryBytes;
    }
    public sealed class ProbeResult {
        public int DriverApiVersion; public DeviceInfo[] Devices;
    }
    public static class CudaDriverProbe {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryEx(string file, IntPtr reserved, uint flags);
        [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
        private static extern IntPtr GetProcAddress(IntPtr module, string name);
        [DllImport("kernel32.dll")]
        private static extern bool FreeLibrary(IntPtr module);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate int Init(uint flags);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate int GetInt(out int value);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate int GetDevice(out int device, int ordinal);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate int GetName(StringBuilder value, int length, int device);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate int GetCapability(out int major, out int minor, int device);
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate int GetMemory(out ulong bytes, int device);
        private static T Proc<T>(IntPtr module, string name) where T : class {
            IntPtr address = GetProcAddress(module, name);
            if (address == IntPtr.Zero) throw new Exception("Driverfunctie ontbreekt: " + name);
            return (T)(object)Marshal.GetDelegateForFunctionPointer(address, typeof(T));
        }
        private static void Check(int code, string operation) {
            if (code != 0) throw new Exception(operation + " geeft CUDA-resultaat " + code + ".");
        }
        public static ProbeResult Read(string systemCudaPath) {
            // Volledig systeempad, dependency search uitsluitend System32 + DLL-map.
            IntPtr module = LoadLibraryEx(systemCudaPath, IntPtr.Zero, 0x00000900);
            if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                Check(Proc<Init>(module, "cuInit")(0), "cuInit");
                int api, count;
                Check(Proc<GetInt>(module, "cuDriverGetVersion")(out api), "cuDriverGetVersion");
                Check(Proc<GetInt>(module, "cuDeviceGetCount")(out count), "cuDeviceGetCount");
                var devices = new List<DeviceInfo>();
                for (int index = 0; index < count; index++) {
                    int device, major, minor; ulong bytes;
                    var name = new StringBuilder(256);
                    Check(Proc<GetDevice>(module, "cuDeviceGet")(out device, index), "cuDeviceGet");
                    Check(Proc<GetName>(module, "cuDeviceGetName")(name, name.Capacity, device), "cuDeviceGetName");
                    Check(Proc<GetCapability>(module, "cuDeviceComputeCapability")(out major, out minor, device), "cuDeviceComputeCapability");
                    Check(Proc<GetMemory>(module, "cuDeviceTotalMem_v2")(out bytes, device), "cuDeviceTotalMem_v2");
                    devices.Add(new DeviceInfo { Index = index, Name = name.ToString(), Major = major, Minor = minor, MemoryBytes = bytes });
                }
                return new ProbeResult { DriverApiVersion = api, Devices = devices.ToArray() };
            } finally { FreeLibrary(module); }
        }
    }
}
'@
            }
            $probe = [LichtFeldPortable.CudaDriverProbe]::Read($cudaPath)
            $cudaApiVersion = $probe.DriverApiVersion
            if ($cudaApiVersion -ge 12080) { Add-Check 'CUDA-driver API' 'PASS' "Driver-API $cudaApiVersion ondersteunt CUDA 12.8 of nieuwer." }
            else { Add-Check 'CUDA-driver API' 'FAIL' "Driver-API $cudaApiVersion; voor dit pakket is CUDA 12.8 vereist." }
            foreach ($gpu in $probe.Devices) {
                $supported = ($gpu.Major -gt 7 -or ($gpu.Major -eq 7 -and $gpu.Minor -ge 5))
                $gpuResults += [pscustomobject]@{
                    Index = $gpu.Index; Name = $gpu.Name
                    ComputeCapability = ('{0}.{1}' -f $gpu.Major, $gpu.Minor)
                    MemoryGiB = [Math]::Round($gpu.MemoryBytes / 1GB, 2)
                    MeetsMinimum = $supported
                }
                $detail = "GPU $($gpu.Index): $($gpu.Name); compute $($gpu.Major).$($gpu.Minor); $([Math]::Round($gpu.MemoryBytes / 1GB, 2)) GiB VRAM."
                if ($supported) { Add-Check 'NVIDIA GPU' 'PASS' $detail }
                else { Add-Check 'NVIDIA GPU' 'WARN' "$detail Deze GPU haalt minimum compute 7.5 niet." }
            }
            if (@($gpuResults | Where-Object { $_.MeetsMinimum }).Count -eq 0) {
                Add-Check 'Geschikte GPU' 'FAIL' 'Geen toegankelijke NVIDIA GPU met compute capability >=7.5 gevonden.'
            } else { Add-Check 'Geschikte GPU' 'PASS' 'Minstens een GPU voldoet; selecteer in LichtFeld de geschikte GPU.' }
        } catch { Add-Check 'CUDA/GPU-probe' 'FAIL' $_.Exception.GetBaseException().Message }
    }
}

$dependencyLog = [IO.Path]::Combine([IO.Path]::GetDirectoryName($jsonPath), ([IO.Path]::GetFileNameWithoutExtension($jsonPath) + '-pe.json'))
if ($packageExists) {
    $dependencyScript = Join-Path $PSScriptRoot 'Test-PeDependencies.ps1'
    if (Test-Path -LiteralPath $dependencyScript -PathType Leaf) {
        try {
            $existingDirs = @($AdditionalSearchDirectory | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) -PathType Container })
            # De call operator geeft het script een eigen scope. Zijn exit stelt
            # LASTEXITCODE in en keert terug naar dit aanroepende script.
            & $dependencyScript -PackageRoot $root -JsonOutputPath $dependencyLog -AdditionalSearchDirectory $existingDirs
            $dependencyExit = $LASTEXITCODE
            if ($dependencyExit -eq 0) { Add-Check 'PE/DLL-afhankelijkheden' 'PASS' 'Statische imports gecontroleerd; detailrapport in gebruikers-temp.' }
            else { Add-Check 'PE/DLL-afhankelijkheden' 'FAIL' "Statische dependencycontrole geeft exitcode $dependencyExit. Zie $dependencyLog." }
        } catch { Add-Check 'PE/DLL-afhankelijkheden' 'FAIL' $_.Exception.Message }
    } else { Add-Check 'PE/DLL-afhankelijkheden' 'FAIL' 'Test-PeDependencies.ps1 ontbreekt naast dit script.' }
}

Add-Check 'Functionele validatie' 'INFO' 'Dit is een hardware-/driver-/integriteitscontrole. GUI-start, Python-imports, training, weergave, bewerken en exporteren moeten nog met een echt project worden getest.'
$failures = @($checks.ToArray() | Where-Object { $_.Status -eq 'FAIL' })
$report = [pscustomobject]@{
    SchemaVersion = 1
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    PackageRoot = $root
    Passed = ($failures.Count -eq 0)
    MinimumPackageDriver = $minimumDriver.ToString()
    RecommendedDriver = $recommendedDriver.ToString()
    DriverVersion = $(if ($driverVersion) { $driverVersion.ToString() } else { $null })
    CudaDriverApiVersion = $cudaApiVersion
    MinimumComputeCapability = '7.5'
    Gpus = @($gpuResults)
    Checks = @($checks.ToArray())
    PeDependencyReport = $dependencyLog
    DriverPolicy = '571.96 is de conservatieve pakketgrens bij de gepinde CUDA 12.8.0-installer (Table 1). CUDA 12.8.0 Table 3 noemt 570.65; CUDA 12.x minor compatibility noemt 528.33 en heeft beperkingen. 572.61 hoort bij CUDA 12.8 Update 1/2. Nieuwe GPU-modellen kunnen een hogere driver vereisen.'
    Sources = @($sourceGa, $sourceUpdate)
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
Write-Host "JSON-rapport: $jsonPath"
if ($failures.Count -eq 0) {
    Write-Host 'Voorcontroles geslaagd. Voer vervolgens de functionele test in de handleiding uit.' -ForegroundColor Green
    exit 0
}
Write-Host "$($failures.Count) controle(s) mislukt. Het pakket is op deze computer nog niet gevalideerd." -ForegroundColor Red
exit 1

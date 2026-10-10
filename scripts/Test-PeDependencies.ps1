#Requires -Version 5.1
<#
.SYNOPSIS
Leest de PE-importtabellen van EXE-, DLL- en PYD-bestanden zonder ontwikkeltools.
.DESCRIPTION
Dit is een statische controle; LoadLibrary/dlopen-imports, Python-imports, plugins,
resources, GPU-kernels en werkelijke Windows-loaderzoekpaden worden niet uitgevoerd.
Windows-systeem-DLLs worden alleen geaccepteerd wanneer het geen bekende
herdistribueerbare ontwikkelruntime is. NVIDIA-driver-DLLs worden nooit gebundeld.
.EXAMPLE
.\Test-PeDependencies.ps1 -PackageRoot C:\Users\naam\LichtFeld
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [string[]]$AdditionalSearchDirectory = @(),
    [Alias('ReportPath')][string]$JsonOutputPath,
    [switch]$AllowPackageElsewhere,
    [switch]$AllowMissingDriver
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Read-PeImports {
    param([string]$Path)
    $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'Read')
    $reader = New-Object System.IO.BinaryReader($stream)
    try {
        function Read-U16([long]$Offset) {
            if ($Offset -lt 0 -or $Offset + 2 -gt $stream.Length) { throw 'PE-bestand afgekapt (UInt16).' }
            $stream.Position = $Offset
            return $reader.ReadUInt16()
        }
        function Read-U32([long]$Offset) {
            if ($Offset -lt 0 -or $Offset + 4 -gt $stream.Length) { throw 'PE-bestand afgekapt (UInt32).' }
            $stream.Position = $Offset
            return $reader.ReadUInt32()
        }
        function Read-U64([long]$Offset) {
            if ($Offset -lt 0 -or $Offset + 8 -gt $stream.Length) { throw 'PE-bestand afgekapt (UInt64).' }
            $stream.Position = $Offset
            return $reader.ReadUInt64()
        }
        if ((Read-U16 0) -ne 0x5A4D) { throw 'Geen MZ/PE-bestand.' }
        $pe = [long](Read-U32 0x3C)
        if ((Read-U32 $pe) -ne 0x00004550) { throw 'Geen geldige PE-signatuur.' }
        $machine = Read-U16 ($pe + 4)
        $sectionCount = Read-U16 ($pe + 6)
        $optionalSize = Read-U16 ($pe + 20)
        $optional = $pe + 24
        $magic = Read-U16 $optional
        if ($magic -eq 0x20B) {
            $directoryOffset = $optional + 112
            $directoryCount = Read-U32 ($optional + 108)
            $imageBase = Read-U64 ($optional + 24)
        } elseif ($magic -eq 0x10B) {
            $directoryOffset = $optional + 96
            $directoryCount = Read-U32 ($optional + 92)
            $imageBase = [uint64](Read-U32 ($optional + 28))
        } else { throw ('Onbekend PE optional-header-formaat: 0x{0:X}.' -f $magic) }
        $headersSize = Read-U32 ($optional + 60)
        $sectionOffset = $optional + $optionalSize
        if ($sectionCount -gt 4096 -or $sectionOffset + ([long]$sectionCount * 40) -gt $stream.Length) {
            throw 'Ongeldige PE-sectietabel.'
        }
        $sections = @()
        for ($index = 0; $index -lt $sectionCount; $index++) {
            $offset = $sectionOffset + $index * 40
            $sections += [pscustomobject]@{
                VirtualSize = [long](Read-U32 ($offset + 8))
                VirtualAddress = [long](Read-U32 ($offset + 12))
                RawSize = [long](Read-U32 ($offset + 16))
                RawOffset = [long](Read-U32 ($offset + 20))
            }
        }
        function Convert-Rva([long]$Rva) {
            if ($Rva -lt 0) { throw 'Negatieve PE-RVA.' }
            if ($Rva -lt $headersSize -and $Rva -lt $stream.Length) { return $Rva }
            foreach ($section in $sections) {
                if ($Rva -ge $section.VirtualAddress -and $Rva -lt $section.VirtualAddress + [Math]::Max($section.VirtualSize, $section.RawSize)) {
                    $delta = $Rva - $section.VirtualAddress
                    if ($delta -ge $section.RawSize -or $section.RawOffset + $delta -ge $stream.Length) {
                        throw 'PE-RVA verwijst buiten de opgeslagen sectie.'
                    }
                    return $section.RawOffset + $delta
                }
            }
            throw ('PE-RVA 0x{0:X} niet gevonden.' -f $Rva)
        }
        function Read-DllName([long]$Rva) {
            $offset = Convert-Rva $Rva
            $stream.Position = $offset
            $bytes = New-Object 'System.Collections.Generic.List[byte]'
            for ($index = 0; $index -lt 4096 -and $stream.Position -lt $stream.Length; $index++) {
                $value = $reader.ReadByte()
                if ($value -eq 0) {
                    $name = [Text.Encoding]::ASCII.GetString($bytes.ToArray())
                    if ([string]::IsNullOrWhiteSpace($name) -or $name -match '[\\/:]') { throw 'Ongeldige DLL-naam in importtabel.' }
                    return $name.ToLowerInvariant()
                }
                if ($value -lt 32 -or $value -gt 126) { throw 'Ongeldige tekens in DLL-importnaam.' }
                $bytes.Add($value)
            }
            throw 'DLL-importnaam niet nul-beeindigd.'
        }
        $imports = @()
        foreach ($definition in @(@{ Index = 1; Size = 20; Kind = 'Import' }, @{ Index = 13; Size = 32; Kind = 'DelayImport' })) {
            if ($directoryCount -le $definition.Index) { continue }
            $directoryEntry = $directoryOffset + $definition.Index * 8
            if ($directoryEntry + 8 -gt $optional + $optionalSize) { throw 'PE-data-directory buiten optional header.' }
            $rva = [long](Read-U32 $directoryEntry)
            $size = [long](Read-U32 ($directoryEntry + 4))
            if ($rva -eq 0) { continue }
            if ($size -lt $definition.Size) { throw 'PE-importdirectory heeft een ongeldige grootte.' }
            $maximum = [Math]::Min([long][Math]::Floor($size / $definition.Size), 65536)
            $terminated = $false
            for ($index = 0; $index -lt $maximum; $index++) {
                $descriptor = Convert-Rva ($rva + $index * $definition.Size)
                $nonzero = $false
                for ($field = 0; $field -lt $definition.Size; $field += 4) {
                    if ((Read-U32 ($descriptor + $field)) -ne 0) { $nonzero = $true }
                }
                if (-not $nonzero) { $terminated = $true; break }
                if ($definition.Index -eq 1) {
                    $nameRva = [long](Read-U32 ($descriptor + 12))
                } else {
                    $attributes = Read-U32 $descriptor
                    $nameRva = [long](Read-U32 ($descriptor + 4))
                    if (($attributes -band 1) -eq 0) {
                        if ([uint64]$nameRva -lt $imageBase) { throw 'Delay-import VA ligt onder image base.' }
                        $nameRva = [long]([uint64]$nameRva - $imageBase)
                    }
                }
                $imports += [pscustomobject]@{ Name = (Read-DllName $nameRva); Kind = $definition.Kind }
            }
            if (-not $terminated) { throw 'PE-importdirectory bevat geen afsluitende descriptor.' }
        }
        return [pscustomobject]@{ Machine = ('0x{0:X4}' -f $machine); IsX64 = ($machine -eq 0x8664); Imports = @($imports) }
    } finally { $reader.Dispose(); $stream.Dispose() }
}

$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PackageRoot).ProviderPath).TrimEnd([char[]]'\/')
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'PackageRoot moet een map zijn.' }
$rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
$searchDirectories = @($root, (Join-Path $root 'bin'))
foreach ($directory in $AdditionalSearchDirectory) {
    if ([IO.Path]::IsPathRooted($directory)) { $resolved = [IO.Path]::GetFullPath($directory) }
    else { $resolved = [IO.Path]::GetFullPath((Join-Path $root $directory)) }
    if (-not $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -and $resolved -ne $root) {
        throw 'AdditionalSearchDirectory moet binnen het pakket liggen.'
    }
    $searchDirectories += $resolved
}
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object { $_.Extension -match '^\.(exe|dll|pyd)$' })
$fileIndex = @{}
foreach ($file in $files) {
    $name = $file.Name.ToLowerInvariant()
    if (-not $fileIndex.ContainsKey($name)) { $fileIndex[$name] = @() }
    $fileIndex[$name] += $file.FullName
}
$systemDirectory = [Environment]::GetFolderPath('System')
$driverNames = @('nvcuda.dll', 'nvapi64.dll', 'nvapi.dll', 'nvml.dll', 'nvoptix.dll', 'nvcuvid.dll', 'nvencodeapi64.dll', 'nvencodeapi.dll', 'nvidia-ml.dll', 'nvidia-opencl.dll')
# Deze DLLs mogen niet toevallig van een ontwikkelcomputer worden "geleend".
$redistributablePattern = '^(vcruntime|msvcp|msvcr|concrt|vcomp|cudart|cublas|cufft|curand|cusolver|cusparse|cudnn|nvrtc|nvjitlink|python|torch|c10|tbb|libiomp|libomp|zlib|libcrypto|libssl)'
$results = @()
$issues = New-Object 'System.Collections.Generic.List[string]'
$warnings = New-Object 'System.Collections.Generic.List[string]'
if ($files.Count -eq 0) { $issues.Add('Geen EXE-, DLL- of PYD-bestanden aangetroffen; er is geen build om te controleren.') }
foreach ($driverName in $driverNames) {
    if ($fileIndex.ContainsKey($driverName)) { $issues.Add("Driver-DLL mag niet worden gebundeld: $driverName.") }
}
foreach ($file in $files) {
    $relative = $file.FullName.Substring($rootPrefix.Length)
    try {
        $pe = Read-PeImports $file.FullName
        if (-not $pe.IsX64) { $issues.Add("Geen AMD64-binary: $relative ($($pe.Machine)).") }
        foreach ($dependency in $pe.Imports) {
            $name = $dependency.Name
            $resolvedPath = $null
            $classification = 'Missing'
            if ($name -match '^(api-ms-|ext-ms-)') {
                $classification = 'WindowsApiSet'
            } elseif ($driverNames -contains $name) {
                $systemCandidate = Join-Path $systemDirectory $name
                $classification = 'NvidiaDriver'
                if (Test-Path -LiteralPath $systemCandidate -PathType Leaf) { $resolvedPath = $systemCandidate }
                if (-not $resolvedPath -and -not $AllowMissingDriver) { $issues.Add("NVIDIA-driver-DLL ontbreekt op deze computer: $name (geimporteerd door $relative).") }
            } else {
                foreach ($directory in @($file.DirectoryName) + $searchDirectories) {
                    $candidate = Join-Path $directory $name
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $resolvedPath = $candidate; $classification = 'PackageSearchPath'; break }
                }
                if (-not $resolvedPath -and $fileIndex.ContainsKey($name)) {
                    $classification = 'PackageElsewhere'
                    $resolvedPath = $fileIndex[$name][0]
                    $message = "DLL staat elders in pakket; loaderzoekpad moet worden bevestigd: $name <- $relative."
                    if ($AllowPackageElsewhere) { $warnings.Add($message) } else { $issues.Add($message) }
                }
                if (-not $resolvedPath -and ($name -eq 'msvcrt.dll' -or $name -notmatch $redistributablePattern)) {
                    $candidate = Join-Path $systemDirectory $name
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        # Alleen Microsoft-systeemcomponenten; een willekeurige System32-DLL is geen portable dependency.
                        $company = [Diagnostics.FileVersionInfo]::GetVersionInfo($candidate).CompanyName
                        if ($company -match '^Microsoft') { $resolvedPath = $candidate; $classification = 'WindowsSystem' }
                    }
                }
                if (-not $resolvedPath) { $issues.Add("DLL ontbreekt in pakket: $name <- $relative ($($dependency.Kind)).") }
            }
            $results += [pscustomobject]@{ File = $relative; Dll = $name; ImportKind = $dependency.Kind; Classification = $classification; ResolvedPath = $resolvedPath }
        }
    } catch { $issues.Add("PE-controle mislukt voor ${relative}: $($_.Exception.Message)") }
}
$report = [pscustomobject]@{
    SchemaVersion = 1
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    PackageRoot = $root
    BinaryCount = $files.Count
    ImportCount = $results.Count
    Passed = ($issues.Count -eq 0)
    AllowMissingDriver = [bool]$AllowMissingDriver
    SearchDirectories = @($searchDirectories)
    Dependencies = @($results)
    Errors = @($issues.ToArray() | Select-Object -Unique)
    Warnings = @($warnings.ToArray() | Select-Object -Unique)
    Limitations = 'Statische normale en delay-imports; geen dynamische DLL/Python/plugin-imports, resources, loaderuitvoering of GPU-training.'
}
if ($JsonOutputPath) {
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $JsonOutputPath -Encoding UTF8
    Write-Host "JSON-rapport: $JsonOutputPath"
}
Write-Host "PE-controle: $($files.Count) binaries, $($results.Count) imports, $($report.Errors.Count) fouten, $($report.Warnings.Count) waarschuwingen."
foreach ($message in $report.Errors) { Write-Host "FOUT: $message" -ForegroundColor Red }
foreach ($message in $report.Warnings) { Write-Host "LET OP: $message" -ForegroundColor Yellow }
Write-Host "Beperking: $($report.Limitations)"
if ($report.Passed) { exit 0 } else { exit 1 }

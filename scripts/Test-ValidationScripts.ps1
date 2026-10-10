#Requires -Version 5.1
<#
.SYNOPSIS
Test de controlescripts op Windows zonder productbuild, SDK of NVIDIA GPU.
.DESCRIPTION
Dit testharnas gebruikt een ongewijzigde kopie van de Windows cmd.exe voor een
echte PE-importcontrole en kleine synthetische PE-tabellen voor negatieve cases.
Geen fixture wordt uitgevoerd. Manifesttests beoordelen uitsluitend de manifest-
en applicatiebestandchecks: de volledige doelcomputercontrole mag zonder GPU
terecht falen. Een groene test bewijst geen werkende LichtFeld-productbuild.
.EXAMPLE
.\scripts\Test-ValidationScripts.ps1 -ReportPath .\validation-scripts.json
#>
[CmdletBinding()]
param(
    [string]$ReportPath = (Join-Path ([IO.Path]::GetTempPath()) 'lichtfeld-validation-scripts.json'),
    [switch]$KeepFixtures
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitProcess) {
    throw 'Voer deze tests uit met 64-bit PowerShell op Windows.'
}
$peChecker = Join-Path $PSScriptRoot 'Test-PeDependencies.ps1'
$targetChecker = Join-Path $PSScriptRoot 'Test-TargetComputer.ps1'
foreach ($script in @($peChecker, $targetChecker)) {
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw "Controlescript ontbreekt: $script" }
}
$tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
$testRoot = Join-Path $tempPrefix ('lf-validator-tests-' + [Guid]::NewGuid().ToString('N'))
$reportDirectory = Join-Path $testRoot 'reports'
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$cases = New-Object 'System.Collections.Generic.List[object]'

function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Test-Case([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        $cases.Add([pscustomobject]@{ Name = $Name; Passed = $true; Error = $null })
        Write-Host "PASS: $Name"
    } catch {
        $cases.Add([pscustomobject]@{ Name = $Name; Passed = $false; Error = $_.Exception.Message })
        Write-Host "FAIL: $Name - $($_.Exception.Message)" -ForegroundColor Red
    }
}

function New-Fixture([string]$Name) {
    $directory = Join-Path $testRoot ('fixtures\' + $Name)
    New-Item -ItemType Directory -Path (Join-Path $directory 'bin') -Force | Out-Null
    return $directory
}

function Write-PeFixture {
    param([string]$Path, [string]$ImportDll, [string]$DelayDll, [switch]$Pe32, [switch]$DelayUsesVa)
    # Alleen headers/importtabellen, zonder code. Deze fixture mag niet starten.
    $data = New-Object byte[] 1024
    function Put-U16([int]$Offset, [uint16]$Value) { [BitConverter]::GetBytes($Value).CopyTo($data, $Offset) }
    function Put-U32([int]$Offset, [uint32]$Value) { [BitConverter]::GetBytes($Value).CopyTo($data, $Offset) }
    Put-U16 0 0x5A4D
    Put-U32 0x3C 0x80
    Put-U32 0x80 0x4550
    Put-U16 0x84 $(if ($Pe32) { 0x14C } else { 0x8664 })
    Put-U16 0x86 1
    Put-U16 0x94 240
    Put-U32 (0x98 + 60) 512
    if ($Pe32) {
        Put-U16 0x98 0x10B
        Put-U32 (0x98 + 28) 0x400000
        Put-U32 (0x98 + 92) 16
        $directories = 0x98 + 96
    } else {
        Put-U16 0x98 0x20B
        Put-U32 (0x98 + 108) 16
        $directories = 0x98 + 112
    }
    Put-U32 (0x188 + 8) 512
    Put-U32 (0x188 + 12) 0x1000
    Put-U32 (0x188 + 16) 512
    Put-U32 (0x188 + 20) 512
    if ($ImportDll) {
        Put-U32 ($directories + 8) 0x1000
        Put-U32 ($directories + 12) 40
        Put-U32 (512 + 12) 0x1040
        [Text.Encoding]::ASCII.GetBytes($ImportDll).CopyTo($data, 512 + 64)
    }
    if ($DelayDll) {
        Put-U32 ($directories + 104) 0x1080
        Put-U32 ($directories + 108) 64
        if ($DelayUsesVa) {
            Assert-That ([bool]$Pe32) 'VA delay-importfixture vereist PE32.'
            Put-U32 (512 + 128) 0
            Put-U32 (512 + 132) (0x400000 + 0x10C0)
        } else {
            Put-U32 (512 + 128) 1
            Put-U32 (512 + 132) 0x10C0
        }
        [Text.Encoding]::ASCII.GetBytes($DelayDll).CopyTo($data, 512 + 192)
    }
    [IO.File]::WriteAllBytes($Path, $data)
}

function Invoke-PeFixture {
    param([string]$Name, [string]$Root, [int]$ExpectedExit, [string[]]$SearchDirectories = @(), [switch]$AllowMissingDriver)
    $json = Join-Path $reportDirectory ($Name + '.json')
    $log = Join-Path $reportDirectory ($Name + '.log')
    & $peChecker -PackageRoot $Root -JsonOutputPath $json -AdditionalSearchDirectory $SearchDirectories -AllowMissingDriver:$AllowMissingDriver *> $log
    $actualExit = $LASTEXITCODE
    Assert-That ($actualExit -eq $ExpectedExit) "Exitcode $actualExit; verwacht $ExpectedExit. Zie $log."
    $report = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
    Assert-That ([bool]$report.Passed -eq ($ExpectedExit -eq 0)) 'Passed-status en exitcode komen niet overeen.'
    return $report
}

function Invoke-TargetFixture([string]$Name, [string]$Root) {
    $json = Join-Path $reportDirectory ($Name + '.json')
    $log = Join-Path $reportDirectory ($Name + '.log')
    & $targetChecker -PackageRoot $Root -JsonOutputPath $json *> $log
    # Geen assert op GPU/driver of globale exitcode: CI hoeft geen GPU te hebben.
    return (Get-Content -LiteralPath $json -Raw | ConvertFrom-Json)
}

function Assert-TargetCheck([object]$Report, [string]$Name, [string]$Status, [string]$DetailPattern) {
    $matching = @($Report.Checks | Where-Object { $_.Name -eq $Name })
    Assert-That ($matching.Count -eq 1) "Controle ontbreekt of dubbel: $Name."
    Assert-That ($matching[0].Status -eq $Status) "Controle $Name geeft $($matching[0].Status); verwacht $Status."
    if ($DetailPattern) { Assert-That ($matching[0].Detail -match $DetailPattern) "Verwachte diagnose ontbreekt bij $Name." }
}

function Write-Manifest([string]$Root, [string[]]$Lines) {
    $Lines | Set-Content -LiteralPath (Join-Path $Root 'SHA256SUMS.txt') -Encoding ASCII
}

try {
    Test-Case 'PowerShell parsers accepteren beide controlescripts' {
        foreach ($script in @($peChecker, $targetChecker)) {
            $tokens = $null; $parseErrors = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$parseErrors)
            Assert-That (@($parseErrors).Count -eq 0) "Parserfout in $script."
        }
    }

    Test-Case 'Echte Windows x64-binary: systeem-DLLs en API sets' {
        $root = New-Fixture 'windows-stock'
        Copy-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe') -Destination (Join-Path $root 'bin\cmd.exe')
        $report = Invoke-PeFixture 'windows-stock' $root 0
        Assert-That ($report.BinaryCount -eq 1 -and $report.ImportCount -gt 0) 'Geen echte imports gelezen.'
        Assert-That (@($report.Dependencies | Where-Object { $_.Classification -in @('WindowsSystem', 'WindowsApiSet') }).Count -eq $report.ImportCount) 'Windows cmd.exe afhankelijkheid niet als systeemcomponent herkend.'
    }

    Test-Case 'Normale en RVA delay-imports worden beide gelezen' {
        $root = New-Fixture 'normal-delay'
        Write-PeFixture (Join-Path $root 'bin\test.exe') 'kernel32.dll' 'api-ms-win-core-synch-l1-2-0.dll'
        $report = Invoke-PeFixture 'normal-delay' $root 0
        Assert-That ($report.ImportCount -eq 2) 'Verwacht twee imports.'
        Assert-That (@($report.Dependencies | Where-Object { $_.ImportKind -eq 'DelayImport' }).Count -eq 1) 'Delay-import overgeslagen.'
    }

    Test-Case 'Ontbrekende normale import faalt' {
        $root = New-Fixture 'missing-import'
        Write-PeFixture (Join-Path $root 'bin\test.exe') 'lichtfeld-fixture-missing.dll' $null
        $report = Invoke-PeFixture 'missing-import' $root 1
        Assert-That ($report.Dependencies[0].Classification -eq 'Missing') 'Ontbrekende DLL niet gedetecteerd.'
    }

    Test-Case 'Ontbrekende delay-import faalt' {
        $root = New-Fixture 'missing-delay'
        Write-PeFixture (Join-Path $root 'bin\test.exe') $null 'lichtfeld-fixture-missing.dll'
        $report = Invoke-PeFixture 'missing-delay' $root 1
        Assert-That ($report.Dependencies[0].ImportKind -eq 'DelayImport') 'Ontbrekende delay-import niet gelezen.'
    }

    Test-Case 'DLL elders in pakket faalt; expliciet zoekpad slaagt' {
        $root = New-Fixture 'elsewhere'
        New-Item -ItemType Directory -Path (Join-Path $root 'extensions') -Force | Out-Null
        Write-PeFixture (Join-Path $root 'bin\test.exe') 'fixture.dll' $null
        Write-PeFixture (Join-Path $root 'extensions\fixture.dll') $null $null
        $report = Invoke-PeFixture 'elsewhere-fail' $root 1
        Assert-That ($report.Dependencies[0].Classification -eq 'PackageElsewhere') 'Onbevestigd zoekpad niet herkend.'
        $report = Invoke-PeFixture 'elsewhere-explicit' $root 0 @('extensions')
        Assert-That ($report.Dependencies[0].Classification -eq 'PackageSearchPath') 'Expliciet zoekpad niet gebruikt.'
    }

    Test-Case 'Recursieve PYD-imports worden gecontroleerd' {
        $root = New-Fixture 'nested-pyd'
        New-Item -ItemType Directory -Path (Join-Path $root 'extensions\nested') -Force | Out-Null
        Write-PeFixture (Join-Path $root 'extensions\nested\fixture.pyd') 'lichtfeld-fixture-missing.dll' $null
        $report = Invoke-PeFixture 'nested-pyd' $root 1
        Assert-That ($report.BinaryCount -eq 1 -and $report.ImportCount -eq 1) 'Recursieve PYD niet gecontroleerd.'
    }

    Test-Case 'Gebundelde NVIDIA-driver faalt ook zonder import' {
        $root = New-Fixture 'bundled-driver'
        Write-PeFixture (Join-Path $root 'bin\nvcuda.dll') $null $null
        $report = Invoke-PeFixture 'bundled-driver' $root 1
        Assert-That (($report.Errors -join ' ') -match 'Driver-DLL mag niet') 'Gebundelde driver niet geweigerd.'
    }

    Test-Case 'GPU-loze CI staat alleen expliciet ontbrekende driver toe' {
        $root = New-Fixture 'driver-system'
        Write-PeFixture (Join-Path $root 'bin\test.exe') 'nvcuda.dll' $null
        $report = Invoke-PeFixture 'driver-system' $root 0 @() -AllowMissingDriver
        Assert-That ($report.Dependencies[0].Classification -eq 'NvidiaDriver') 'Driver niet apart geclassificeerd.'
        Assert-That ([bool]$report.AllowMissingDriver) 'CI-uitzondering niet vastgelegd in rapport.'
    }

    Test-Case 'Ontwikkelruntime uit System32 wordt niet als portable beschouwd' {
        $root = New-Fixture 'missing-msvc-runtime'
        Write-PeFixture (Join-Path $root 'bin\test.exe') 'vcruntime140.dll' $null
        $report = Invoke-PeFixture 'missing-msvc-runtime' $root 1
        Assert-That ($report.Dependencies[0].Classification -eq 'Missing') 'MSVC-runtime buiten pakket ten onrechte geaccepteerd.'
    }

    Test-Case 'PE32 met VA delay-import wordt gelezen en x86 geweigerd' {
        $root = New-Fixture 'pe32-va-delay'
        Write-PeFixture (Join-Path $root 'bin\test.exe') $null 'kernel32.dll' -Pe32 -DelayUsesVa
        $report = Invoke-PeFixture 'pe32-va-delay' $root 1
        Assert-That ($report.ImportCount -eq 1 -and $report.Dependencies[0].Dll -eq 'kernel32.dll') 'VA delay-import in PE32 niet correct gelezen.'
        Assert-That (($report.Errors -join ' ') -match 'Geen AMD64-binary') 'x86-architectuur niet geweigerd.'
    }

    Test-Case 'Afgekapt PE-bestand faalt; leeg pakket faalt' {
        $root = New-Fixture 'truncated'
        [IO.File]::WriteAllBytes((Join-Path $root 'bin\test.exe'), [byte[]](0x4D, 0x5A, 0))
        $report = Invoke-PeFixture 'truncated' $root 1
        Assert-That (($report.Errors -join ' ') -match 'afgekapt') 'Afgekapt bestand niet gedetecteerd.'
        $emptyRoot = New-Fixture 'empty'
        $report = Invoke-PeFixture 'empty' $emptyRoot 1
        Assert-That ($report.BinaryCount -eq 0) 'Leeg pakket ten onrechte geaccepteerd.'
    }

    Test-Case 'Zoekpad buiten pakket wordt geweigerd' {
        $root = New-Fixture 'escaped-search'
        $thrown = $false
        try {
            & $peChecker -PackageRoot $root -AdditionalSearchDirectory '..\outside' *> (Join-Path $reportDirectory 'escaped-search.log')
        } catch { $thrown = ($_.Exception.Message -match 'binnen het pakket') }
        Assert-That $thrown 'Zoekpad buiten pakket niet geweigerd.'
    }

    # Voor deze fixtures is cmd.exe alleen een bestaand testbestand met PE-imports.
    # Het wordt nooit uitgevoerd en stelt geen LichtFeld-build voor.
    $manifestRoot = New-Fixture 'manifest'
    $fixtureBinary = Join-Path $manifestRoot 'bin\LichtFeld-Studio.exe'
    Copy-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe') -Destination $fixtureBinary
    $hash = (Get-FileHash -LiteralPath $fixtureBinary -Algorithm SHA256).Hash
    $validLine = $hash + ' *bin/LichtFeld-Studio.exe'

    Test-Case 'Geldig SHA-256-manifest slaagt onafhankelijk van GPU' {
        Write-Manifest $manifestRoot @($validLine)
        $report = Invoke-TargetFixture 'manifest-valid' $manifestRoot
        Assert-TargetCheck $report 'SHA-256-manifest' 'PASS' 'alle hashes kloppen'
        Assert-TargetCheck $report 'Applicatie' 'PASS' 'aanwezig'
    }

    Test-Case 'Verkeerde SHA-256 wordt geweigerd' {
        Write-Manifest $manifestRoot @((('0' * 64) + ' *bin/LichtFeld-Studio.exe'))
        $report = Invoke-TargetFixture 'manifest-bad-hash' $manifestRoot
        Assert-TargetCheck $report 'SHA-256-manifest' 'FAIL' 'wijkt af'
    }

    Test-Case 'Manifest-padtraversal wordt geweigerd' {
        Write-Manifest $manifestRoot @($hash + ' *../outside.exe')
        $report = Invoke-TargetFixture 'manifest-traversal' $manifestRoot
        Assert-TargetCheck $report 'SHA-256-manifest' 'FAIL' 'Pad verlaat pakket'
    }

    Test-Case 'Absoluut manifestpad wordt geweigerd' {
        Write-Manifest $manifestRoot @($hash + ' *' + $fixtureBinary)
        $report = Invoke-TargetFixture 'manifest-absolute' $manifestRoot
        Assert-TargetCheck $report 'SHA-256-manifest' 'FAIL' 'Absoluut pad'
    }

    Test-Case 'Dubbele manifestregel wordt geweigerd' {
        Write-Manifest $manifestRoot @($validLine, $validLine)
        $report = Invoke-TargetFixture 'manifest-duplicate' $manifestRoot
        Assert-TargetCheck $report 'SHA-256-manifest' 'FAIL' 'Dubbel bestand'
    }

    Test-Case 'Niet-genoteerd pakketbestand wordt geweigerd' {
        Write-Manifest $manifestRoot @($validLine)
        'Testbestand' | Set-Content -LiteralPath (Join-Path $manifestRoot 'extra.txt') -Encoding ASCII
        $report = Invoke-TargetFixture 'manifest-unlisted' $manifestRoot
        Assert-TargetCheck $report 'SHA-256-manifest' 'FAIL' 'Niet opgenomen'
        Remove-Item -LiteralPath (Join-Path $manifestRoot 'extra.txt')
    }

    Test-Case 'Ontbrekend manifest is zichtbaar als waarschuwing' {
        Remove-Item -LiteralPath (Join-Path $manifestRoot 'SHA256SUMS.txt')
        $report = Invoke-TargetFixture 'manifest-missing' $manifestRoot
        Assert-TargetCheck $report 'SHA-256-manifest' 'WARN' 'ontbreekt'
    }
} catch {
    $cases.Add([pscustomobject]@{ Name = 'Testharnas voorbereiden/uitvoeren'; Passed = $false; Error = $_.Exception.Message })
    Write-Host "FAIL: Testharnas - $($_.Exception.Message)" -ForegroundColor Red
} finally {
    $failures = @($cases.ToArray() | Where-Object { -not $_.Passed })
    $summary = [pscustomobject]@{
        SchemaVersion = 1
        TimestampUtc = [DateTime]::UtcNow.ToString('o')
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Passed = ($failures.Count -eq 0)
        TestCount = $cases.Count
        FailureCount = $failures.Count
        Tests = @($cases.ToArray())
        GpuRequired = $false
        Scope = 'Validatie van controlescripts met stock Windows PE, synthetische importtabellen en SHA-256-manifestfixtures. Geen LichtFeld-build, GUI, Python-runtime, CUDA-kernel of training gevalideerd.'
        FixturesRetained = [bool]($KeepFixtures -or $failures.Count -gt 0)
        FixtureRoot = $testRoot
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    if (-not $summary.FixturesRetained) {
        $resolvedFixtureRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $testRoot).ProviderPath)
        if (-not $resolvedFixtureRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolvedFixtureRoot -Leaf) -notmatch '^lf-validator-tests-[0-9a-f]{32}$') {
            throw 'Tijdelijke testmap heeft onverwacht pad; opruimen geweigerd.'
        }
        Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force
    }
}
Write-Host "Controlescripttests: $($cases.Count) cases; $($failures.Count) fouten. Rapport: $ReportPath"
if ($failures.Count -gt 0) { exit 1 }
exit 0

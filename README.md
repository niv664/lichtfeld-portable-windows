# LichtFeld Studio portable Windows x64

Deze afzonderlijke repository bouwt gratis uit de officiële GPLv3-broncode. Er worden geen bestaande repositories, Railway-projecten of productieomgevingen gebruikt.

Vastgelegde applicatie: **v0.5.4**, commit `09d338189162b52d888fdbe2c88025e31d0dea05`. De upstream Windows-portable workflow heeft deze versie succesvol gebouwd op 9 oktober 2026. Deze packaging voert een eigen build en aanvullende controles uit. [Officiële broncode](https://github.com/MrNeRF/LichtFeld-Studio/tree/09d338189162b52d888fdbe2c88025e31d0dea05), [officiële geslaagde packagingrun](https://github.com/MrNeRF/LichtFeld-Studio/actions/runs/37933415849).

## Download en gebruik

Open [Releases](https://github.com/niv664/lichtfeld-portable-windows/releases). Een geslaagde build publiceert `LichtFeld-Studio-v0.5.4-portable-windows-x64.zip`, checksum en bijbehorend bronarchief. Tot er een geslaagde release is, staat de actuele status bij [Actions](https://github.com/niv664/lichtfeld-portable-windows/actions/workflows/portable-windows.yml).

De doelcomputer heeft Windows x64, een NVIDIA-GPU met compute capability >=7.5 en een geschikte driver nodig. Deze distributie hanteert >=571.96 bij de gepinde CUDA12.8.0-toolchain. Git, CMake, Visual Studio, een externe Python-installatie en de CUDA Toolkit zijn op de doelcomputer niet nodig. Open na uitpakken `bin/LichtFeld-Studio.exe` of `Start-LichtFeld.cmd`. Lees [de Nederlandse handleiding](docs/INSTALLATIE-NL.md).

## Zelf bouwen

De bouwcomputer vereist Windows x64, PowerShell7, Git, CMake>=3.30, Ninja, Visual Studio2022>=17.10 met Desktop development with C++ en C++ Clang Compiler for Windows, en de officiële CUDA12.8.0 Toolkit. Alleen de bouwcomputer heeft deze tools nodig. De standaard-app gebruikt geen LibTorch; de afzonderlijke upstream GPU-unittests wel.

Gebruik een korte, afzonderlijke, lege werkmap op een schijf met ruime vrije capaciteit. De eerste vcpkg-installatie is groot en duurt langer dan een build met cache. Voer uit vanuit deze repository:

```powershell
# Alleen indien de CUDA Toolkit nog niet aanwezig is, op de bouwcomputer.
.\scripts\Install-CudaBuildTools.ps1
.\scripts\Build-Portable.ps1 -Workspace C:\lfp -Stage All -Jobs 2 -VcpkgJobs 2
.\scripts\New-PortablePackage.ps1 -Workspace C:\lfp
```

Installeer noodzakelijke bouwtools via [Microsoft](https://visualstudio.microsoft.com/downloads/), [NVIDIA](https://developer.nvidia.com/cuda-12-8-0-download-archive), [CMake](https://cmake.org/download/), [Ninja](https://github.com/ninja-build/ninja/releases) en [Git](https://git-scm.com/download/win). Volg de licentievoorwaarden van de bouwtools. Voor een andere locatie ondersteunt het bouwscript `-VsInstallationPath` en `-CudaPath`. Het script wijzigt geen systeeminstellingen, installeert geen tools en weigert onbekende bestaande broncheckouts.

## GitHub Actions

Kies **Actions > Portable Windows x64 > Run workflow**. De standaard publiceert bij succes automatisch een release. Het standaard Windows2022-runnerimage bevat VS2022/MSVC/Clang/CMake/Ninja; de workflow controleert die tools en installeert de officieel ondertekende CUDA12.8.0 Toolkit zonder NVIDIA-driver. Officiële Actions en beide bronrepositories zijn op exacte commits vastgezet. De workflow bouwt met `windows-release`, `BUILD_PORTABLE=ON`, PTX voor compute75+, ingebouwde Python en uv, en uitgeschakelde ontwikkelpaden.

De build heeft maximaal350 minuten. Op publieke repositories zijn standaard GitHub-hosted Actions-builds gratis; deze workflow vraagt geen betaalde runner aan. De standaard publiceert grote downloads rechtstreeks op GitHub Releases. Actions-artifactopslag heeft een beperkte gratis accountquota; alleen als je publiceren uitzet wordt het hele pakket drie dagen als artifact bewaard. De dependency-cache blijft binnen de standaard repository-cachelimiet; deze configuratie wijzigt geen budgetten of betaalinstellingen. Een eerste build zonder vcpkg-cache kan uren duren. Bij falen worden de kleine diagnostische logs zeven dagen bewaard. [GitHub Actions-gebruik en opslag](https://docs.github.com/en/billing/concepts/product-billing/github-actions), [upstream Windowsvereisten](https://github.com/MrNeRF/LichtFeld-Studio/blob/09d338189162b52d888fdbe2c88025e31d0dea05/docs/building_and_distribution.md).

## Wijzigingen ten opzichte van upstream

`patches/portable-paths.patch` verwijdert één te brede Windows-DLL-exclusie en schakelt de twee absolute Python-ontwikkelpaden uit bij portable builds. Packaging voegt de door upstream build gebruikte maar niet geïnstalleerde `lfs_splat_lod_hierarchy.py` toe aan `bin/`. Er zijn geen wijzigingen aan training, rendering of export. vcpkg wordt volledig gekloond zodat historische portfiles tijdens configuratie zonder lazy Git-netwerkrequests beschikbaar zijn.

De ZIP behoudt upstream layout: `bin/`, `Lib/`, `DLLs/`, `extensions/` en `share/LichtFeld-Studio/`. Licenties en een SHA256-manifest worden aangevuld. Het bronarchief bevat de exacte applicatie met submodule, patch en scripts, de vcpkg-recepten, gedownloade dependencybronnen en beschikbare gepatchte bronbomen. De bronarchives worden samen met de binary-cache bewaard zodat hergebruik van binaries hun bijbehorende oorspronkelijke bronnen behoudt.

## Validatie

Packagingcontrole leest alle normale en delay PE-imports en vereist app-local redistributables. De distributie wordt naar een tijdelijke map met spaties verplaatst. Gebundelde Python standaardlibraries, beide interne helpers en uv worden daar met een Windows-only PATH getest. `--help` wordt alleen gestart als een echte NVIDIA-driver aanwezig is. De checksumcontrole voorkomt onopgemerkte ontbrekende/veranderde bestanden. `package-tests.json` vermeldt de daadwerkelijke uitslagen.

Een Actions-runner heeft geen NVIDIA-GPU. Deze workflow valideert geen training, GUI-rendering, GPU-kernels of exports. Gebruik [GPU-TESTPROTOCOL.md](docs/GPU-TESTPROTOCOL.md) op echte hardware. De doelcomputercontrole is een voorafgaande inspectie en vervangt die functionele test niet.

## Licenties en imports

Zie [LICENTIES.md](docs/LICENTIES.md) voor GPLv3, broncode en dependencyvoorwaarden. Deze packaging is eveneens GPLv3-or-later. Zie [FOTO-VIDEO-IMPORT.md](docs/FOTO-VIDEO-IMPORT.md) voor JPG/PNG, bestaande native FFmpeg-frame-extractie en latere COLMAP-integratie. COLMAP en extra FFmpeg-binaries worden in deze eerste versie niet toegevoegd.

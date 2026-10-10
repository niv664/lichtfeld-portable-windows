# Licenties en verdere distributie van LichtFeld Studio

Deze packaging gebruikt LichtFeld Studio **v0.5.4**, broncommit `09d338189162b52d888fdbe2c88025e31d0dea05`. De applicatie is GPLv3; de meegeleverde libraries, lettertypen en Python-runtime behouden hun eigen licenties. Gebruik en gratis verspreiding zijn verschillende handelingen: wie een binary doorgeeft, moet ook de voorwaarden voor die distributie nakomen. [Upstream licentie](https://github.com/MrNeRF/LichtFeld-Studio/blob/09d338189162b52d888fdbe2c88025e31d0dea05/LICENSE)

## Wat bij de binary hoort

Bewaar de GPL-licentie, de upstream auteursvermeldingen, `THIRD_PARTY_LICENSES.md`, de volledige dependencylicenties en eventuele NOTICE- en PATENTS-bestanden. Het overzicht van upstream verwijst ook naar inspiratiebronnen; het is op zichzelf geen volledige inventaris van daadwerkelijk gebundelde onderdelen. Maak daarom een inventaris op basis van de concrete build en het ZIP-bestand. [Upstream dependencyoverzicht](https://github.com/MrNeRF/LichtFeld-Studio/blob/09d338189162b52d888fdbe2c88025e31d0dea05/THIRD_PARTY_LICENSES.md)

De inventaris moet minimaal bevatten:

- Voor elke vcpkg-package: naam, versie, baseline/port, copyrightbestand uit `vcpkg_installed/<triplet>/share/<package>/copyright` en toepasselijke notices.
- Voor vendored en externe broncode: de bijbehorende LICENSE-, COPYING-, NOTICE- en PATENTS-bestanden, inclusief onderliggende third-party onderdelen.
- Voor lettertypen en pictogrammen: hun originele licentiebestanden, waaronder OFL voor de toepasselijke fonts.
- Voor gebundelde CPython en uv: hun eigen licentieteksten en third-party notices. uv komt uit de door upstream vastgelegde officiële Astral-release.
- Voor NVIDIA- en Microsoft-runtimebestanden: de voorwaarden en notices van de exact gebruikte SDK/toolchain, met een lijst van meegeleverde DLL-bestanden.

## Bijbehorende broncode

Bij een downloadbare binary moet de bijbehorende broncode even toegankelijk zijn, zonder extra kosten, met duidelijke verwijzingen naast de binary. Die broncode omvat ook wijzigingen en scripts die nodig zijn voor genereren en installeren. Markeer eigen wijzigingen met datum en beschrijving. [GPLv3 secties 1, 5 en 6](https://github.com/MrNeRF/LichtFeld-Studio/blob/09d338189162b52d888fdbe2c88025e31d0dea05/LICENSE)

Publiceer bij iedere binaryversie een passend bronpakket met:

1. De exacte upstream checkout, inclusief de inhoud en commit van `external/libvterm` en eventuele overige submodules. Een automatisch GitHub source-archief bevat die submodule-inhoud niet.
2. Deze packagingrepository, buildconfiguratie, lockgegevens, patches, PowerShell-scripts en de buildmanifesten.
3. De gebruikte historische vcpkg-portfiles en overlays, originele dependencybronarchieven en alle toegepaste patches met hun buildscripts. Daarmee kunnen ook Windows-onbruikbare Unix-symlinks uit het originele bronarchief opnieuw worden hersteld.
4. De relevante externe bronbomen en alle licentiebestanden, inclusief de gebruikte FFmpeg- en x264-bronversies.

Archiveer daarvoor de relevante `vcpkg/downloads`, `vcpkg/buildtrees` en externe bronbomen tijdens de build. Gebruik de buildlogs en pakketmetadata om de inventaris te controleren. Een downloadcache of volledige buildtree is een hulpmiddel voor die controle; controleer dat het uiteindelijke bronpakket de benodigde bronbestanden en patches daadwerkelijk bevat. De algemene verwijzing naar de actuele upstream hoofdtak vervangt de broncode van de uitgebrachte binary niet.

## CUDA-runtime

De CUDA 12.8 EULA noemt onder meer `cudart`, `curand`, `nvjpeg`, `nvrtc` en `nvrtc-builtins` als herdistribueerbare onderdelen; versienummers in bestandsnamen zijn toegestaan. Bundel uitsluitend onderdelen die de applicatie nodig heeft en die in de toepasselijke lijst staan, onder de NVIDIA-voorwaarden. Neem de bijbehorende EULA en notices over. Bundel geen volledige Toolkit, ontwikkeltools of Windows `nvcuda.dll`: die DLL komt van de NVIDIA-driver op de doelcomputer. [CUDA 12.8 EULA, secties 1.1.2 en 2.6](https://docs.nvidia.com/cuda/archive/12.8.0/eula/index.html)

De NVIDIA-bestanden worden door dit pakket niet onder de GPL hergelicentieerd. De upstream GPL-licentie bevat geen expliciete CUDA-linkuitzondering. Toestemming voor NVIDIA-redistributie en GPL-compatibiliteit van een gekoppelde combinatie zijn afzonderlijke vragen. Een aanvullende uitzondering kan alleen worden gegeven door de rechthebbenden; deze packaging geeft die toestemming niet en bevestigt geen juridische beoordeling van de combinatie. [GNU uitleg over GPL en andere libraries](https://www.gnu.org/licenses/gpl-faq.en.html#GPLIncompatibleLibs)

## Microsoft-runtime en FFmpeg

Microsoft staat distributie van daarvoor aangewezen Visual C++-runtimebestanden toe onder de toepasselijke Visual Studio-licentie. Gebruik de officiële Redist-map/lijst; plaats benodigde Release-runtime-DLLs naast de applicatie. Distribueer geen Debug-runtime. Voor deze portable uitvoering is geen Visual Studio-installatie op de doelcomputer nodig. [Microsoft distributiedocumentatie](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170)

De standaard LichtFeld-build bevat FFmpeg en x264 via vcpkg. x264 activeert GPL-voorwaarden; de exacte FFmpeg-configuratie bepaalt de licentie van de build. Bewaar de configure-opties, licenties, broncode en patches. Een FFmpeg-build met `--enable-nonfree` is niet herdistribueerbaar; publiceer zo'n build niet. Eventuele codecpatenten zijn niet automatisch afgehandeld door een open-sourcelicentie. [FFmpeg licentie-informatie](https://ffmpeg.org/legal.html)

## Praktische overdracht

Geef bij verdere overdracht de binary, controlebestanden, licenties en verwijzing naar de exacte bijbehorende broncode samen door. Houd deze bronnen beschikbaar zolang de gekozen distributieroute dat vereist. De gebruiksvoorwaarden van de werkcomputer en bedrijfssoftwarebeleid blijven van toepassing.

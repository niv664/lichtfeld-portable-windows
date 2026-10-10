# LichtFeld Studio gebruiken op je Windows-werkcomputer

Deze portable versie hoeft niet geïnstalleerd te worden. Je hebt Windows64-bit, een NVIDIA-GPU met compute capability7.5 of hoger en een geschikte NVIDIA-driver nodig. De pakketcontrole hanteert driver571.96 of hoger. Je hebt op de werkcomputer geen Codex, ChatGPT, Visual Studio, Git, CMake, externe Python-omgeving of volledige CUDA Toolkit nodig.

## 1. Downloaden

Ga naar [GitHub Releases](https://github.com/niv664/lichtfeld-portable-windows/releases). Download het bestand met `portable-windows-x64.zip` in de naam en het bijbehorende `.zip.sha256`-bestand. Het `corresponding-source.tar.gz`-bestand is de bijbehorende broncode, niet het programma. Is nog geen release beschikbaar, bekijk dan [de Actions-build](https://github.com/niv664/lichtfeld-portable-windows/actions/workflows/portable-windows.yml); een geslaagde run biedt hetzelfde pakket onder Artifacts aan. Voor Actions-artifacts kan een GitHub-aanmelding nodig zijn.

Je kunt de download op je voorbereidingscomputer controleren met de gewone Windows PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath '.\LichtFeld-Studio-v0.5.4-portable-windows-x64.zip'
```

Vergelijk de volledige hash met het `.sha256`-bestand. Veranderde of beschadigde downloads gebruik je niet. Download bij een nieuwe release steeds ZIP en checksum van dezelfde release.

## 2. Uitpakken

Klik met de rechtermuisknop op de ZIP en kies **Alles uitpakken**. Gebruik een gewone gebruikersmap, bijvoorbeeld `Documenten\LichtFeld-Studio`. Bij een Actions-artifact zit het portable ZIP-bestand mogelijk binnen de eerste download; pak daarna ook dat ZIP-bestand uit.

Bewaar de hele uitgepakte structuur samen. In de hoofdmap staan de handleiding en startscript; het uitvoerbare bestand staat in `bin\LichtFeld-Studio.exe`. De mappen `Lib`, `DLLs`, `extensions`, `share` en de DLLs in `bin` horen bij de applicatie. Kopieer voor overdracht de volledige map.

## 3. Computer controleren

Dubbelklik op `Controleer-computer.cmd`. De controle leest de GPU, NVIDIA-driver, pakketbestanden, SHA256-manifest en DLL-imports. Het rapport wordt in je tijdelijke gebruikersmap geschreven; het venster toont het pad. Administratorrechten zijn niet nodig. Een groene controle zegt dat de voorafgaande inspectie geslaagd is; GPU-training en weergave moeten daarna daadwerkelijk worden getest.

Als PowerShell door bedrijfsbeleid geblokkeerd is, laat IT de scripts beoordelen of gebruik de applicatie volgens het goedgekeurde bedrijfsproces. Verander geen execution policy en schakel geen beveiliging uit. Een ontbrekende of oudere NVIDIA-driver moet via het normale bedrijfsproces worden bijgewerkt.

## 4. Starten en snelkoppeling

Dubbelklik op `Start-LichtFeld.cmd` of open `bin\LichtFeld-Studio.exe`. Je kunt een bureaubladsnelkoppeling maken door op de EXE rechts te klikken en **Meer opties weergeven > Kopiëren naar > Bureaublad (snelkoppeling maken)** te kiezen. Bij de eerste start kan het compileren van PTX-kernels extra tijd kosten. Dat gebeurt door de NVIDIA-driver; de CUDA Toolkit hoeft niet aanwezig te zijn.

Dit is een uit broncode gebouwde, niet digitaal ondertekende distributie. Volg bij SmartScreen-, antivirus- of IT-meldingen het normale goedkeuringsproces van je organisatie. De handleiding vraagt niet om blokkeringen te omzeilen.

## 5. Eerste project

Gebruik eerst een kleine, echte COLMAP-dataset: een map `images` met de beelden en een bijbehorende `sparse\0` met `cameras.bin`, `images.bin` en `points3D.bin`. Een losse fotomap is nog geen trainingsdataset. Zie `FOTO-VIDEO-IMPORT.md` voor voorbereiding van eigen foto's en video.

Start in LichtFeld een nieuw project en kies de dataset. Controleer of de camera's en sparse punten worden weergegeven. Kies een eigen uitvoermap in je Documenten en begin met een korte training op lagere beeldresolutie. Bekijk het resultaat, sla het project op, stop en hervat de training. Exporteer vervolgens een PLY-, SPZ- of SOG-bestand en open dat opnieuw in de viewer.

De instellingen moeten bij de beschikbare VRAM passen. De lokaal gecontroleerde RTX3050Ti heeft4GB VRAM; een klein project is daarom een geschikte eerste test. Dit geeft nog geen garantie dat een volledige dronecollectie past. Gebruik het protocol in `GPU-TESTPROTOCOL.md` om de eerste echte hardwaretest vast te leggen.

## 6. Overdracht en gegevens

De applicatie kan gebruikersvoorkeuren, modeldownloads en pluginomgevingen in Windows-gebruikersmappen bewaren. Portable betekent hier dat de programmamap zonder installatie overdraagbaar is; alle persoonlijke instellingen worden daardoor niet automatisch meegenomen. Extra plugins of preprocessmodellen kunnen internet vereisen. Het normale trainingsproject gebruikt je lokale gereconstrueerde dataset.

Neem voor verder trainen ook je originele dataset, project en checkpoints mee. Maak een kopie van je originele dronebeelden en houd ze buiten uitvoer- en extractiemappen. Verwijder de portable programmamap wanneer je de toepassing niet meer nodig hebt; ruim persoonlijke projecten alleen zelf op.

## Problemen herkennen

Een melding over een ontbrekende DLL betekent vaak dat de ZIP niet volledig is uitgepakt of dat een beveiligingsproduct een bestand heeft verwijderd. Pak het originele pakket opnieuw uit in een nieuwe map en voer de controle uit. Meld blokkerende beveiliging bij IT. Een CUDA-driverfout vraagt om een geschikte driver. Een VRAM-fout vraagt om een kleiner project of lagere trainingsinstellingen. Bewaar het controlescript-rapport en de applicatielog wanneer je hulp vraagt.

Het pakket bevat `BUILD-MANIFEST.json` met de exacte broncommit en `SHA256SUMS.txt` met alle meegeleverde bestandscontroles. De bijbehorende broncode en licenties staan naast de download. Zie `LICENTIES.md` voordat je het pakket verder verspreidt.

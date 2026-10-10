# Foto en video verwerken voor Gaussian Splatting

LichtFeld Studio v0.5.4 traint op een gereconstrueerde dataset met foto's, camera-informatie en een sparse puntenwolk. Een losse map JPG/PNG-bestanden of een MP4/MOV-bestand levert die camera-informatie nog niet. De betrouwbare route is: beelden voorbereiden, camera's reconstrueren met COLMAP en daarna de dataset in LichtFeld Studio openen. Georeferentie is voor dit visuele proces niet nodig. [LichtFeld Studio broncode en mogelijkheden](https://github.com/MrNeRF/LichtFeld-Studio/tree/09d338189162b52d888fdbe2c88025e31d0dea05)

## Wat deze versie al bevat

De upstream applicatie heeft **File > Extract Video Frames**. Deze functie gebruikt ingebouwde FFmpeg-libraries en kan frames als PNG of JPEG opslaan, met instellingen voor tijdsbereik, interval/FPS en resolutie. Daarvoor hoeft geen losse `ffmpeg.exe` te worden toegevoegd. De beschikbaarheid van een decoder hangt af van de video en de gebundelde codecconfiguratie; MP4 en MOV zijn containers, geen garantie dat elke codec wordt ondersteund. [Native frame-extractie](https://github.com/MrNeRF/LichtFeld-Studio/blob/09d338189162b52d888fdbe2c88025e31d0dea05/src/io/video_frame_extractor.cpp)

Bewaar originele opnamen apart. Kies voor frame-extractie een nieuwe uitvoermap. Gebruik scherpe beelden met veel overlap, parallax en verschillende camerastandpunten. Bij video helpt een beperkt frameaantal om bijna identieke beelden te vermijden. Controleer de beelden op bewegingsonscherpte, overbelichting en bewegende objecten voordat je de reconstructie start. [COLMAP opnameadvies](https://colmap.github.io/tutorial.html)

## COLMAP dataset maken

COLMAP wordt in deze portable versie niet toegevoegd. Gebruik voor de voorbereiding de officiële COLMAP Windows-release en behoud de volledige uitgepakte distributie met libraries en `COLMAP.bat`. Het batchbestand stelt de juiste librarypaden in. [Officiële COLMAP installatie](https://colmap.github.io/install.html)

Maak een nieuwe projectmap, bijvoorbeeld:

```text
MijnScene/
  images/
    beeld000001.jpg
    beeld000002.jpg
  sparse/
```

Voer de onderstaande stappen uit op de voorbereidingscomputer. Pas de twee paden aan; kies een nieuwe projectmap zodat bestaand werk behouden blijft. Controleer de opties met `COLMAP.bat <commando> -h` van de gebruikte release. [COLMAP commandoregel](https://colmap.github.io/cli.html)

```powershell
$colmap = 'C:\Tools\COLMAP\COLMAP.bat'
$scene = 'C:\Users\jouwnaam\Documents\MijnScene'

& $colmap feature_extractor --database_path "$scene\database.db" --image_path "$scene\images"
if ($LASTEXITCODE -ne 0) { throw 'Feature-extractie mislukt' }

& $colmap exhaustive_matcher --database_path "$scene\database.db"
if ($LASTEXITCODE -ne 0) { throw 'Matching mislukt' }

New-Item -ItemType Directory -Path "$scene\sparse" -Force | Out-Null
& $colmap mapper --database_path "$scene\database.db" --image_path "$scene\images" --output_path "$scene\sparse"
if ($LASTEXITCODE -ne 0) { throw 'Reconstructie mislukt' }
```

Voor beelden uit een video kan `sequential_matcher` worden gebruikt in plaats van `exhaustive_matcher`. Houd de oorspronkelijke volgorde van frames aan. Bij grote, ongeordende fotocollecties moeten matchinginstellingen worden afgestemd op het aantal beelden en de overlap. Het resultaat kan meerdere modellen bevatten; controleer welk model voldoende beelden heeft geregistreerd en visueel samenhangend is.

De gebruikelijke uitvoer bevat `sparse/0/cameras.bin`, `images.bin` en `points3D.bin`; tekstmodellen met `.txt` worden ook ondersteund. Bewaar de bijbehorende `images`-map en bestandsnamen. Een dense mesh is niet nodig voor de normale Gaussian Splatting-route. Camera-model en lensvervorming moeten wel bij de beelden passen. [LichtFeld datasetloader](https://github.com/MrNeRF/LichtFeld-Studio/blob/09d338189162b52d888fdbe2c88025e31d0dea05/src/io/include/io/loader.hpp)

## Trainen en overdragen

Open in LichtFeld Studio een nieuw project met de gereconstrueerde dataset. Controleer camera's en sparse punten, begin met een korte training en controleer daarna de beeldkwaliteit. Sla het project op, stop en hervat de training als test en exporteer een splatbestand, bijvoorbeeld PLY, SPZ of SOG. Een exportbestand om alleen te bekijken is niet hetzelfde als een volledig trainingsproject. [Upstream werkproces](https://github.com/MrNeRF/LichtFeld-Studio/blob/09d338189162b52d888fdbe2c88025e31d0dea05/README.md)

Neem voor training op een andere computer ook de dataset en gebruikte checkpoints mee. Project- en datasetpaden moeten op de doelcomputer bereikbaar zijn. Begin daar met een klein project om de GPU-runtime, viewer, training, opslag en export te controleren voordat je grote droneopnamen verwerkt.

## Integratie in een volgende versie

Een aanvullende importfunctie kan de bestaande frame-extractie verbinden met een afzonderlijk, vastgelegd COLMAP-proces. Laat die functie een nieuwe projectmap gebruiken, voortgang tonen, logs bewaren en stoppen bij mislukte opdrachten. Voeg COLMAP alleen toe als de volledige officiële distributie en haar dependencylicenties zijn geïnventariseerd en de reconstructie op echte foto's en video is getest. COLMAP zelf heeft een BSD-licentie; dependencylicenties blijven afzonderlijk gelden. [COLMAP licentie](https://colmap.github.io/license.html)

Als later een zelfstandige FFmpeg-commandoregel nodig is, bouw die uit een vaste officiële bronrelease met vastgelegde opties en checksums. FFmpeg publiceert zelf broncode; de Windows-binaries op zijn downloadpagina zijn externe builds. Het huidige pakket voegt die binaries daarom niet toe. [FFmpeg downloads](https://ffmpeg.org/download.html)

Valideer zo'n uitbreiding met JPG en PNG, H.264 en H.265 in MP4/MOV, rotatiemetadata, HDR-opnamen, paden met spaties, annuleren, mislukte reconstructies en een herstart vanuit de verplaatste portable map. Leg apart vast welke codecs en echte opnamebestanden succesvol zijn verwerkt.

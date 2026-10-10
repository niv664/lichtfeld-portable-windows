# Functionele test op een echte NVIDIA-computer

GitHub Actions bouwt het programma en controleert bestanden, DLL-imports en verplaatste Python/uv-runtime. Het volgende protocol controleert het echte gebruik. Leg GPU, VRAM, driver, Windowsversie, `BUILD-MANIFEST.json`, testdataset en uitslagen vast. Gebruik een kleine echte dataset; maak geen definitieve kwaliteitsclaim op basis van synthetische input.

1. Pak de ZIP uit op een Windowscomputer zonder ontwikkeltools, of in een Windowsomgeving waarin de applicatie geen ontwikkelpaden kan gebruiken. Voer `Controleer-computer.cmd` uit en bewaar het JSON-rapport. Test vanuit een nieuwe locatie met spaties in het pad.
2. Start `bin\LichtFeld-Studio.exe` rechtstreeks en via `Start-LichtFeld.cmd`. Controleer splashscreen, fonts, iconen, vensters en locales. Controleer dat er geen ontbrekende DLL-, Python- of resourcefout optreedt.
3. Open een kleine echte COLMAP-dataset. Controleer camera's, afbeeldingen en sparse punten. Gebruik een nieuwe gebruikers-uitvoermap. Start een korte training en leg iteraties, resolutie, VRAM-gebruik, tijd en eventuele fouten vast.
4. Beweeg de camera tijdens training, controleer het splatbeeld en stop de training. Sla op, sluit de app en hervat vanuit het checkpoint. Controleer dat voortgang en model behouden blijven.
5. Selecteer een beperkt aantal splats, voer een bewerking uit, gebruik undo en redo, en sla een projectkopie op. Controleer het resultaat na heropenen.
6. Exporteer PLY, SPZ en SOG naar nieuwe bestanden. Open elke export opnieuw en controleer inhoud en weergave. Test de zelfstandige HTML-viewerexport afzonderlijk indien je die gebruikt.
7. Gebruik File > Extract Video Frames met een korte eigen MP4/MOV-testclip, naar een nieuwe map. Controleer frameaantal, oriëntatie en beeldinhoud. Leg de werkelijke codec vast; succes met één clip bewijst geen algemene codecondersteuning.
8. Verplaats de volledige applicatiemap, herstart en herhaal openen/viewer/export. Houd originele beelden ongewijzigd. Controleer bij de verplaatsing ook projectpaden en gebruikersvoorkeuren.

Rapporteer per stap PASS/FAIL/SKIPPED met de reden. Een gestart venster of geslaagde `--help` is geen bewijs van training, export of fotorealistische kwaliteit. De lokale RTX3050Ti met4GB kan kleine scenes testen; resultaten daarop bewijzen geen geheugenlimiet of snelheid op een andere werkcomputer.

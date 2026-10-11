# Guide du Technicien & Déploiement Matériel — GymDesk V3

Ce guide accompagne le technicien lors du déploiement physique de GymDesk sur le poste de réception d'un club de sport.

---

## 1. Déploiement Rapide sur Clé USB (Portable, Zéro Installation)
GymDesk est fourni dans un dossier portable autonome `GymDesk_USB/` :
1. **Copier le dossier `GymDesk_USB`** sur une clé USB standard.
2. **Brancher la clé USB** sur le PC / Laptop de réception sous Windows 10 ou 11.
3. **Double-cliquer sur `Lancer_GymDesk.bat`**.
   - Le serveur local et pilote matériel `access_agent.exe` démarre en arrière-plan sur le port 47811.
   - Microsoft Edge s'ouvre en **mode kiosque dédié (`--app=http://127.0.0.1:47811`)** sans onglets, sans barre d'adresse ni barre de recherche, avec l'apparence exacte d'un logiciel de bureau natif.
4. Aucune dépendance Visual Studio, Dart, Flutter ou C++ n'est requise sur le PC client.

---

## 2. Branchement & Pilotes des Lecteurs Biométriques
1. **Suprema BioMini / BioMini Plus 2 / BioMini Slim 2** :
   - Brancher sur un port USB 2.0 ou 3.0 direct (éviter les hubs USB non alimentés).
   - Les pilotes Suprema officiels (`UFScanner Driver`) sont pré-packagés dans l'agent d'accès.
   - Dans le Gestionnaire de Périphériques Windows, l'appareil apparaît sous **Biometric Devices** ou **USB Devices** avec le VID `0x1612`.
2. **HID DigitalPersona (U.are.U 4500)** :
   - Brancher sur le port USB (VID `0x05BA`, PID `0x000A`).
   - Le capteur clignote en bleu à l'initialisation.
3. **ZKTeco (Live20R, ZK4500)** :
   - VID `0x1B55` / `0x2724`.
4. **SecuGen (Hamster Pro 20)** :
   - VID `0x1162`.

---

## 3. Outil de Diagnostic et Validation Terrain
1. Ouvrir GymDesk et naviguer vers **Paramètres > Lecteurs d'empreintes & Diagnostic**.
2. Cliquer sur **Identifier les lecteurs USB** (`/settings/biometrics/identify`) :
   - Vérifier que l'appareil est détecté avec le badge vert **Compatible Officiel**.
   - Si l'appareil n'apparaît pas, cliquer sur **Rafraîchir** ou changer de port USB.
3. Cliquer sur **Diagnostic du capteur** (`/settings/biometrics/diagnostic`) :
   - Cliquer sur **Capturer Empreinte Test**.
   - Poser un doigt : la qualité doit dépasser 70% et la latence doit être inférieure à 800ms.
   - Tester l'impulsion de porte avec le bouton **Tester l'ouverture de la porte**.

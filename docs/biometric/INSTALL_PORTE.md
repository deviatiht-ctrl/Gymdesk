# Schéma de Câblage & Contrôle de Porte — GymDesk V3

Ce guide s'adresse aux installateurs et électriciens pour le raccordement du relais d'ouverture de porte GymDesk.

---

## 1. Vue d'Ensemble de l'Installation
```
[ PC / Laptop GymDesk ]
        | (USB)
[ Relais USB Série CH340 / FTDI ] ou [ Relais IP / Ethernet ]
        |
   Contact Sec (NO / COM)
        |
[ Alimentation 12V DC ] ---- ( + ) ---- [ Gâche Électrique ou Ventouse Magnétique ]
        |                                        |
       ( - ) ------------------------------------'
```

---

## 2. Types de Verrouillage & Sécurité
1. **Gâche Électrique Standard (Fail-Secure / Émission)** :
   - Porte verrouillée en l'absence de courant.
   - Branchement sur le contact **NO (Normalement Ouvert)** du relais.
   - À la détection d'une empreinte valide, GymDesk envoie une impulsion de **3 secondes** pour alimenter la gâche et libérer le loquet.
2. **Ventouse Électromagnétique (Fail-Safe / Rupture)** :
   - Porte verrouillée tant que le courant circule.
   - En cas de coupure de courant générale ou alarme incendie, la porte s'ouvre automatiquement pour l'évacuation.
   - Branchement sur le contact **NC (Normalement Fermé)** du relais.
   - GymDesk coupe l'alimentation pendant **3 secondes** pour libérer la ventouse.

---

## 3. Configuration du Module Relais dans GymDesk
Dans **Paramètres > Lecteurs d'empreintes & Diagnostic (`/settings/biometrics`)** :
1. **Mode de relais** : Sélectionner `Relais USB Série` ou `Relais IP / HTTP`.
2. **Port Série** : Renseigner le port COM identifié dans le Gestionnaire de Périphériques Windows (ex: `COM3`, `COM4`).
3. **Durée de l'impulsion** : Régler entre 1 et 10 secondes (recommandé : **3 secondes**).
4. **Bouton de test** : Cliquer sur **Tester l'ouverture de la porte** pour déclencher le claquement du relais et valider le câblage sans attendre un membre.

---

## 4. Bouton Poussoir de Sortie (Bouton Échappatoire)
- Câbler un bouton poussoir "Demande de Sortie" (Push to Exit) en parallèle du contact de commande NO (ou en série pour NC).
- Permet aux membres à l'intérieur de la salle de sortir librement sans poser leur doigt sur le capteur.

# Protocole de Test Matériel & Recette — GymDesk V3

Ce protocole permet de valider le fonctionnement de la chaîne biométrique et du contrôle de porte avant mise en production dans la salle.

---

## 1. Matrice de Tests Matériels

| N° | Étape de Test | Procédure | Résultat Attendu | Statut |
|---|---|---|---|---|
| **T01** | Détection USB PnP | Brancher le lecteur Suprema BioMini sur le PC de réception. | Le voyant du capteur s'allume. L'outil d'identification affiche le VID `0x1612` et PID `0x000B`. | [ ] |
| **T02** | Capture de test | Ouvrir le diagnostic et cliquer sur "Capturer Empreinte Test". | Doigt détecté en < 500ms, score de qualité NFIQ >= 75%. | [ ] |
| **T03** | Détection de faux doigt (LFD) | Poser une feuille ou un matériau inerte sur le capteur Suprema. | Rejet immédiat avec code d'erreur `fake_finger_detected`. | [ ] |
| **T04** | Enrôlement 2 doigts | Inscrire un nouveau membre dans le Magicien (Doigt principal + Secours). | Les deux gabarits sont chiffrés et stockés dans la base. | [ ] |
| **T05** | Détection de doublon 1:N | Tenter d'enrôler un deuxième membre avec le même doigt. | Alerte instantanée bloquant l'enregistrement avec le nom du titulaire d'origine. | [ ] |
| **T06** | Accès Membre Actif | Poser le doigt d'un membre avec abonnement à jour sur l'écran Kiosque (`/door_access`). | Écran vert "ACCÈS AUTORISÉ", impulsion de 3s au relais, présence enregistrée. | [ ] |
| **T07** | Accès Membre Expiré | Poser le doigt d'un membre dont la date de fin d'abonnement est dépassée. | Écran rouge "ACCÈS REFUSÉ — ABONNEMENT EXPIRÉ", relais inactif, bouton de renouvellement proposé. | [ ] |
| **T08** | Déclenchement Relais Porte | Cliquer sur "Tester l'ouverture de la porte" dans les paramètres. | Claquement physique du relais, déverrouillage de la gâche / ventouse pendant 3s. | [ ] |
| **T09** | Ouverture Manuelle Secours | Déclencher l'ouverture manuelle depuis la barre d'accueil. | Impulsion relais envoyée, événement `door_manual_open` archivé dans l'audit. | [ ] |
| **T10** | Droit à l'effacement | Supprimer les empreintes d'un membre depuis sa fiche. | Suppression confirmée, tentative d'accès ultérieure retourne "Empreinte non reconnue". | [ ] |

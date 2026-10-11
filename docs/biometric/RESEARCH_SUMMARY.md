# SYNTHÈSE MULTI-FABRICANTS ET DÉCISION D'ARCHITECTURE

Ce document résume les résultats de recherche de la **Phase B** pour l'ensemble des fabricants d'appareils biométriques évalués pour GymDesk.

---

## 1. TABLEAU COMPARATIF DES FABRICANTS

| Fabricant | VID USB | Modèles populaires | SDK Desktop (Win) | SDK Mobile (Android) | Formats de gabarits | Matching 1:N natif | Niveau de confiance |
|---|---|---|---|---|---|---|---|
| **Suprema** (Obligatoire) | `0x1612` | BioMini, BioMini Plus 2, Slim 2 | `UFScanner.dll` + `UFMatcher.dll` | `BioMini_SDK.aar` (OTG) | Propriétaire Suprema (384B), ISO 19794-2, ANSI 378 | Oui (jusqu'à 100k/s) | **Vérifié (Documentation officielle Suprema)** |
| **HID DigitalPersona** | `0x05BA` | U.are.U 4500, U.are.U 5160 | `dpfp.dll` / One Touch SDK | One Touch for Android | ANSI 378, ISO 19794-2, DP Feature Set | Oui | **Vérifié (Pilote & matériel de référence)** |
| **ZKTeco** | `0x1B55` / `0x2724` | ZK4500, ZK9500, Live20R | `zkemkeeper.dll` / ZKFinger SDK | ZKFinger SDK Android | ZKFinger 10.0, ISO 19794-2 | Oui | **Vérifié (Documentation ZKTeco)** |
| **SecuGen** | `0x1162` | Hamster Pro 20, Hamster Plus | `FDx SDK Pro for Windows` | `SecuGen Android SDK` | SecuGen Proprietary, ANSI 378, ISO 19794-2 | Oui | **Vérifié (SecuGen FDx SDK docs)** |

---

## 2. DÉCISION D'ARCHITECTURE

1. **Abstraction en registre découplé (`ReaderRegistry`)** :
   - Aucun composant de l'interface utilisateur ou du domaine d'activité de GymDesk ne dépend directement du SDK d'une marque donnée.
   - Les appels passent par l'interface générique `FingerprintReader`.
2. **Identification USB automatique (Plug-and-Play)** :
   - L'identifiant USB (VID:PID) permet au registre d'instancier automatiquement l'adaptateur adéquat dès que l'appareil est branché.
3. **Format d'échange et de persistance** :
   - Pour chaque doigt enrôlé, GymDesk conserve le gabarit natif du fabricant chiffré (`template_enc`), ainsi que le format international standard **ISO/IEC 19794-2** (`iso_template_enc`).
   - Cela assure la pérennité totale des données : si une salle remplace ses lecteurs Suprema par des ZKTeco ou DigitalPersona, le système peut continuer de comparer les gabarits sans forcer les membres à repasser au poste d'accueil.

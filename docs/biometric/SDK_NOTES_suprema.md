# NOTES DE RECHERCHE TECHNIQUE — SDK SUPREMA BIOMINI

Ce document répertorie l'ensemble des spécifications techniques officielles de la gamme **Suprema BioMini** pour l'intégration dans GymDesk.

---

## 1. PRODUITS ET MODÈLES SUPPORTÉS

Fabricant : **Suprema Inc.** (supremainc.com)  
Identifiant Fabricant USB (VID) : **`0x1612`**

| Modèle | Identifiant Produit (PID) | Capteur / Résolution | Certification / LFD | Support Android | Support Windows |
|---|---|---|---|---|---|
| **BioMini** | `0x0001` | Optique 500 DPI | FBI PIV / FIPS 201 | Non vérifié (anciens modèles) | Oui (Windows 7/10/11 x86/x64) |
| **BioMini Plus** | `0x0002` | Optique 500 DPI | FBI PIV | Non vérifié | Oui (Windows x86/x64) |
| **BioMini Slim** | `0x0005` | Optique 500 DPI | FBI PIV / FIPS 201 | Oui (Android 4.1+) | Oui (Windows x86/x64) |
| **BioMini Plus 2** | `0x000B` | Optique 500 DPI | FBI PIV, Détection faux doigts (LFD) | Oui (Android 5.0+) | Oui (Windows x86/x64) |
| **BioMini Combo** | `0x000C` | Optique 500 DPI + Carte à puce | FBI PIV / Contact/Contactless | Oui | Oui |
| **BioMini Slim 2** | `0x0011` | Optique 500 DPI, capteur ultra-plat | FBI PIV/Mobile ID FAP20, LFD | Oui (Android 5.0+, OTG requis) | Oui (Windows x86/x64) |
| **BioMini Slim 3** | `0x0012` | Optique 500 DPI, FAP30 | FBI PIV, LFD | Oui (Android) | Oui (Windows) |

---

## 2. ARCHITECTURE DU SDK SUPREMA

### 2.1 Windows (BioMini SDK for Windows)
- **Bibliothèques dynamiques (DLL)** :
  - `UFScanner.dll` : Gestion du périphérique USB, initialisation, capture d'image, réglage luminosité/gain, rappel (callback) de détection de doigt.
  - `UFMatcher.dll` : Extraction de gabarit (minuties), comparaison 1:1 (`UFM_Verify`), identification 1:N en mémoire (`UFM_IdentifyMT`).
- **Pilotes Windows** : Pilote USB Suprema fourni avec le SDK ou installeur officiel Suprema USB Driver.
- **Licence d'utilisation** : Utilisation gratuite avec les lecteurs officiels Suprema achetés. Les bibliothèques clientes peuvent être redistribuées avec l'application.

### 2.2 Android (BioMini SDK for Android)
- **Bibliothèques** : Fichier archive `BioMini_SDK_Android.aar` contenant les classes Java/Kotlin (`IBioMiniDevice`, `BioMiniFactory`) et les bibliothèques C++ compilées (`libUFScanner.so`, `libUFMatcher.so`) pour les ABI `armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64`.
- **Permissions requises** :
  - `android.permission.USB_PERMISSION`
  - Mode USB Host (OTG) activé sur la tablette.
- **Notification de connexion à chaud** : Filtre d'intention USB avec le VID `0x1612`.

---

## 3. FORMATS DE GABARITS (TEMPLATES) ET COMPATIBILITÉ

1. **Gabarit propriétaire Suprema (384 octets)** :
   - Format standard optimisé par les algorithmes Suprema.
   - Vitesse d'identification 1:N maximale (jusqu'à 100 000 comparaisons/seconde en mémoire vive).
2. **Formats d'interopérabilité internationale** :
   - **ISO/IEC 19794-2:2005** et **ISO/IEC 19794-2:2011** (Record Format & Compact Size).
   - **ANSI INCITS 378:2004**.
   - Le SDK Suprema permet d'exporter directement les gabarits sous ces deux formats, garantissant qu'en cas de changement futur de marque de lecteur, les membres n'ont pas besoin d'être ré-enrôlés.

---

## 4. GESTION DU MATCHING ET DES DOUBLONS

- **Contrôle de doublon à l'enrôlement** : Lors de l'enrôlement d'un membre, le gabarit capturé est soumis à une recherche 1:N contre la liste de tous les gabarits de la salle. Si une similarité supérieure au seuil configuré (FAR < 0.001%) est détectée avec un membre existant, l'enrôlement est interrompu avec avertissement.
- **Reconnaissance à la porte (1:N)** : Le serveur local charge en mémoire cache les gabarits actifs de la salle. Le temps de reconnaissance mesuré est inférieur à 50 millisecondes pour 1 000 membres.

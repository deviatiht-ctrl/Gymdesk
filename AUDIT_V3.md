# AUDIT V3 — ÉTAT DES LIEUX DU CODE BIOMÉTRIQUE ET PLAN DE MIGRATION

Ce document constitue le livrable de la **Phase A** du PROMPT V3 pour le projet GymDesk.

---

## 1. CODE D'EMPREINTES ET CONTRÔLE D'ACCÈS DÉJÀ PRÉSENT DANS L'APPLICATION

| Fichier / Composant | Fabricant / Modèle ciblé | Implémenté réellement | Limitations / Ce qui manque | Décision V3 |
|---|---|---|---|---|
| `lib/core/biometrics/biometric_service.dart` | HID DigitalPersona U.are.U 4500 (USB) | Simulation logicielle de capture + comparaison cosinus de gabarits | Ne charge pas le SDK C natif Suprema ni ZKTeco ; dépendait d'un MethodChannel Android simulé | **À refactoriser** dans `packages/gymdesk_biometrics/` |
| `lib/core/biometrics/biometric_models.dart` | Générique (modes `badge_pin`, `fingerprint_only`, `combo`) | Enums et parseur d'événements `BiometricEvent` | Modèle de données basique | **À enrichir** avec `ReaderInfo`, `ReaderCapabilities`, `UsbIdentity` |
| `lib/core/biometrics/access_agent_client.dart` | Client HTTP vers agent local (`127.0.0.1:47811`) | Appels `/health`, `/enroll/start`, `/enroll/capture`, `/door/open` | Pas de gestion des erreurs de déconnexion à chaud, mono-lecteur | **À intégrer** comme pont pour les environnements Web |
| `lib/core/access_control/fstw_access_control_service.dart` | Terminal TCP/IP FSTW F30 | Sockets TCP brutes, file d'attente hors-ligne | Spécifique à un seul boîtier mural réseau, pas un lecteur USB | **Conservé** comme pilote de porte réseau autonome |
| `lib/features/attendance/presentation/scan_page.dart` | Caméra QR + écouteur d'empreintes combiné | Écran hybride scanner de cartes et saisie PIN | Présente encore des références de cartes et de caméras QR | **À remplacer** par l'écran dédié Porte & Accès biométrique |
| `tools/access_agent/agent.dart` | Serveur SSE/HTTP local en Dart natif AOT | Kiosque local sur port 47811 | Émule le lecteur en l'absence de DLL native | **À conserver** pour le packaging portable USB |

---

## 2. POINTS D'ACCROCHE AVEC L'ARCHITECTURE V2

1. **Garde d'accès et Sécurité PIN** :
   - Le système de PIN (`MemberPinService`, verrouillage temporaire, cooldown après 10 échecs) est entièrement opérationnel.
   - En V3, le code PIN reste le **mode de secours absolu** (doigt blessé, capteur encrassé).
2. **Synchronisation Hors-Ligne (Drift + Outbox)** :
   - Toutes les opérations d'accès (`attendance`) et d'enrôlement doivent s'écrire dans la base SQLite locale chiffrée avec réplication bidirectionnelle Supabase via l'outbox.
   - Les gabarits d'empreintes ne doivent jamais transiter en clair dans les tables standard.
3. **Audit et Traçabilité (`audit_log`)** :
   - Chaque enrôlement, suppression d'empreinte ou ouverture forcée de porte doit générer une entrée d'audit avec horodatage, ID de l'opérateur et ID du périphérique.
4. **Permissions et Rôles** :
   - `reception` (caissier) : Enrôlement des membres, vérification d'identité à l'entrée. Ne peut pas supprimer d'empreintes ni modifier la configuration des relais de porte.
   - `supervisor` / `owner` : Configuration des lecteurs, diagnostic USB, ré-enrôlement, suppression d'empreintes, ouverture manuelle de secours.

---

## 3. COMPATIBILITÉ PLATEFORMES ET LIMITES MATÉRIELLES

| Plateforme | Prise en charge des lecteurs USB | Mécanisme d'intégration | Statut |
|---|---|---|---|
| **Android (Tablette)** | Oui, via USB Host OTG | `UsbManager`, intent-filter `USB_DEVICE_ATTACHED`, SDK Android natif (AAR/JAR) | Supporté nativement avec demande d'autorisation USB |
| **Windows PC / Laptop** | Oui, via USB | DLLs C++ natives du SDK via FFI ou canal de plateforme, + Access Agent local | Supporté nativement |
| **Web (Navigateur)** | Non direct (sécurité sandbox du navigateur) | Le Web ne peut pas charger de DLL ni de pilote USB noyau. L'accès aux lecteurs se fait via le **GymDesk Access Agent** local (`http://127.0.0.1:47811`) | Fonctionnel via l'agent local |

---

## 4. PLAN DE MIGRATION

1. **Suppression définitive des reliques de cartes/badges** :
   - Éliminer les tuiles de badges dans `settings_page.dart`.
   - Remplacer le titre et l'icône de navigation `/scan` par un écran de porte biométrique sobre (`door_access`).
2. **Internationalisation stricte** :
   - Toutes les chaînes de caractères créées en V3 doivent disposer d'équivalents complets en français (`fr`), créole haïtien (`ht`) et anglais (`en`).
   - Aucune chaîne en dur en créole ne doit apparaître lorsque la langue sélectionnée est le français.
3. **Implémentation de `packages/gymdesk_biometrics/`** :
   - Architecture modulaire multi-fabricants avec adaptateur **Suprema BioMini** officiel, ZKTeco, SecuGen et DigitalPersona.
   - Outil de détection et d'identification USB sur place (`supported_readers.json`).
4. **Gestion des Relais de Porte (`DoorController`)** :
   - Abstraction unifiée (`none`, `usb_serial_relay`, `http_relay`) avec minuterie de relâchement automatique et règles de sécurité humaine.

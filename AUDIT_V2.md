# AUDIT V2 — GYMDESK (État des lieux & Analyse d'écarts)

**Projet** : GymDesk (Flutter + Supabase + Drift)  
**Date d'audit** : 2026-10-06  
**Auditeur** : Développeur Full Stack Senior  

> **Note de relecture (post-implémentation)** : les écarts décrits ci-dessous ont été traités. Implémenté : onboarding + flag persistant, wizard `/signup` via `create_gym_with_owner`, statuts `trial`/`grace`, paywall `/paywall` avec déclaration de paiement et export de données, validation super admin (`/admin/declarations` + statistiques d'essai), lots de badges anonymes CR80 + quotas serveur, activation `/activate` en 4 étapes avec PIN membre PBKDF2 salé (210k itérations) dans `member_pins`, verrouillage kiosque persistant (`/kiosk` + lock-task Android), rôle `supervisor` partout, renouvellements `pending` validés owner/supervisor, entités V2 dans `sync_push`/`sync_pull` (`13_v2_sync.sql`), traductions ht/fr/en complètes. État vérifié : `flutter analyze` sans erreur, 58/58 tests Dart verts. Reste à valider : exécution des migrations SQL sur un projet Supabase réel, tests des Edge Functions déployées, et essais terrain du verrouillage kiosque Android.

---

## 1. État par module

### 1.1 Auth & Sessions
- **Existe et fonctionne** : Authentification Supabase Auth (`email` + `password`), récupération de mot de passe (`passwordRecovery`), verrouillage local par PIN du personnel en cas d'inactivité (`PinService` avec PBKDF2 et dérivation sécurisée), mise en cache sécurisée de la session (`flutter_secure_storage`).
- **Incomplet** : Flux de premier lancement limité à `/startup` -> `/login` ; pas d'onboarding illustré ni de détection du premier lancement ; pas de sign-up autonome pour les propriétaires (`owner`).
- **Manque** : Drapeaux de stockage local pour l'onboarding vu (`has_seen_onboarding`) ; verrouillage scanner kiosque avec déverrouillage par credentials propriétaire/superviseur (en ligne + empreinte salée hors ligne) ; distinction nette entre le PIN personnel/kiosque et le code PIN membre.

### 1.2 Gyms & Provisioning
- **Existe et fonctionne** : Provisioning de salle uniquement via Edge Function / RPC super admin (`provision_gym_begin`, `provision_gym_auth_user`, `provision_gym_finish`), paramètres de salle (`settings` jsonb), branding (`accent_color`, devise, timezone, logo sur bucket `gym-assets`), cycle de vie super admin (suspendre, réactiver, archiver).
- **Incomplet** : Salle créée uniquement par l'admin ; statut restreint à `('active', 'suspended')`.
- **Manque** : Libre-service pour la création de salle par le propriétaire (assistant en 4 étapes) ; champs V2 dans `gyms` (`trial_started_at`, `trial_ends_at`, `onboarding_done`, `suspension_reason`, `source`) ; statut `trial` et `grace` ; Edge Function `create_gym_with_owner` ; vérification d'unicité et anti-abus d'essai.

### 1.3 Members
- **Existe et fonctionne** : Modèle complet avec NIF (validation 10 chiffres), CIN, contact d'urgence, tuteur (< 18 ans), normalisation téléphone (+509), photo JPEG compressée stockée localement puis synchronisée dans storage Supabase, détection de doublons en local (NIF, téléphone, nom/date de naissance).
- **Incomplet** : Les membres sont créés directement avec génération de numéro atomique (`next_member_number` / `gym_counters`) et génération de QR (`qr_token`, `qr_style` par membre) ; formulaires couplés au membre sans badge physique préalable.
- **Manque** : Liaison membre-badge (`members.badge_id`) ; champ `is_test` ; flux d'activation de badge vierge ; code PIN membre (stocké dans `member_pins`).

### 1.4 Plans
- **Existe et fonctionne** : Plans de salle (`duration_days`, `price`, `currency`, `active`, `sort_order`), validation et synchronisation outbox.
- **Incomplet / À adapter** : Plans de membres par défaut créés lors du self-signup (1 mois, 3 mois, 6 mois, 1 an, séance unique).

### 1.5 Subscriptions
- **Existe et fonctionne** : Durées calculées, dates début/fin inclusives, calcul de validité (`member_validity`) gérant fuseau de la salle, jours de grâce et statut `pending`.
- **Incomplet** : Tout rôle staff pouvait créer des abonnements activés immédiatement si payés ; renouvellement sans sas de validation par superviseur/owner.
- **Manque** : Colonnes `validated_by` et `validated_at` dans `subscriptions` ; statut `pending` comme demande de renouvellement bloquante sans droit d'accès tant que non validée ; écran de validation des renouvellements pour `supervisor` et `owner` ; état dérivé `lapsed`.

### 1.6 Payments
- **Existe et fonctionne** : Enregistrement de paiements membres (`cash`, `moncash`, `natcash`, `bank`, `other`), restriction de consultation pour la réception.
- **Manque** : Table `payment_declarations` pour les paiements de licence plateforme faits par les salles (MonCash, NatCash, virement, espèces) avec validation super admin ; table `platform_settings` (coordonnées Cvisual).

### 1.7 Attendance & Scanner
- **Existe et fonctionne** : Scanner avec caméra (`mobile_scanner`) et douchette USB (champ texte autofocus), anti-double lecture (délai paramétrable), append-only attendance locale et serveur, résultat authoritative calculé côté serveur lors du sync.
- **Incomplet** : Analyse du QR au format V1 `GD1|<gym>|<number>|<token>` ; pas d'étape de saisie de PIN membre ; écran standard intégré dans la navigation globale.
- **Manque** : Format QR V2 `GD2|<gym>|<badge_number>|<token>` avec rétrocompatibilité `GD1` ; écran PIN membre plein écran (clavier tactile, disposition optionnelle mélangée, timeout 20s) ; nouveaux motifs de refus (`denied_bad_pin`, `denied_pin_locked`, `denied_unactivated`, `denied_blocked_badge`, `denied_pending_renewal`) ; colonne `pin_verified` et `badge_id` dans `attendance` ; mode kiosque plein écran verrouillé (`startLockTask` Android / fenêtrage Windows).

### 1.8 Badges (QR, Carte, Export)
- **Existe et fonctionne** : Modèles de badge (`badge_templates`), prévisualisation, impression/export PDF CR80 d'un membre individuel via `printing`.
- **Incomplet** : Badges générés à la demande pour chaque membre, avec nom et photo imprimés sur la carte.
- **Manque** : Tables `badge_batches`, `badges`, `badge_history`, vue `badge_state` ; génération par lots de badges anonymes (01, 02...) ; contrôle strict de quota par offre/plan ; design de carte V2 anonyme (logo, nom, téléphone, grand QR 32mm, numéro "MEMBRE 01", verso explicatif sans nom/photo) ; export en planche A4 et ZIP PNG 300 dpi.

### 1.9 Reports & Dashboard
- **Existe et fonctionne** : Métriques dashboard local (`active_members`, entrées du jour, revenus du jour), rapports d'activité exportables en PDF.
- **Incomplet** : Pas de visibilité sur l'état de l'essai, les badges en stock et les demandes de renouvellement.
- **Manque** : Guide de démarrage en 4 étapes cochables ; bandeau d'essai (décompte dynamique, alertes J-3, J-2, J-1, J) ; paywall de fin d'essai.

### 1.10 Billing Plateforme & Super Admin
- **Existe et fonctionne** : Métriques globales de la plateforme (`platform_statistics`), gestion d'état des salles.
- **Incomplet** : Suivi des contrats d'offres de la V1 incomplet au niveau UI.
- **Manque** : Gestion des essais expirant, validation des déclarations de paiement (`payment_declarations`), calcul de conversion, configuration des quotas de badges dans `platform_offers`.

### 1.11 Sync Offline & Local DB
- **Existe et fonctionne** : Drift avec table générique `records`, `outbox`, `sync_metadata`, résolution de conflits, détection de dérive d'horloge (`ClockGuard`).
- **Incomplet** : `LocalDatabase` ne stocke que les entités V1 ; schéma Drift en version 1.
- **Manque** : Migration Drift v2 ; intégration des entités `badges`, `badge_batches`, `badge_history`, `member_pins`, `payment_declarations` ; chiffrement local SQLCipher pour sécuriser les empreintes PIN membre.

### 1.12 Thème, Responsive & Internationalisation
- **Existe et fonctionne** : Couleurs sobres, fond blanc, pas d'emojis, icônes Lucide, police DM Sans, adaptation Laptop/Tablette/Mobile via `LayoutBuilder` et `NavigationRail`, 3 langues : créole haïtien (`ht`), français (`fr`), anglais (`en`) dans `AppStrings`.
- **Incomplet** : Manque l'ensemble des clés de traduction V2 (onboarding, essai, badges par lots, PIN membre, scanner verrouillé, paywall).

---

## 2. Tableau des écarts (Existant -> Cible -> Action)

| Composant | Existant (V1) | Cible (V2) | Action |
|-----------|---------------|------------|--------|
| **Création salle** | Réservée au super admin via Edge Function | Libre-service (assistant 4 étapes) + admin | **Modifier & Créer** |
| **Démarrage** | Écran de login direct | Onboarding (4 écrans) si 1re fois, sinon login/signup | **Créer** |
| **Période d'essai** | Aucune (immédiatement active) | 7 jours calculés serveur, bandeau J-x, paywall automatique | **Créer** |
| **Rôles personnel** | `super_admin`, `owner`, `manager`, `reception` | `super_admin`, `owner`, `supervisor`, `reception` | **Remplacer** (`manager` -> `supervisor`) |
| **Attribution QR** | QR unique généré lors de la création d'un membre | Lots de badges anonymes créés d'avance, activés sur un membre | **Remplacer** |
| **Design du badge** | Carte avec nom et photo du membre | Carte anonyme : Logo, Nom salle, Tél, Numéro, Grand QR (>=32mm) | **Remplacer** |
| **Quota badges** | Illimité | Limité selon l'offre (Essai: 10, per_member: 50, etc.) | **Créer** |
| **Vérification scan** | Scan QR seul donne accès direct | Scan QR puis vérification PIN membre sur pavé numérique | **Remplacer** |
| **PIN Membre** | Inexistant | 4-6 chiffres, Argon2id/PBKDF2 salé, anti-trivial, test mémoire | **Créer** |
| **Mode Kiosque** | Scanner standard avec barre de navigation | Mode verrouillé persistant, déverrouillage email+mdp supervisor/owner | **Créer** |
| **Renouvellement** | Effectif dès encaissement | Validé obligatoirement par `supervisor` ou `owner` | **Modifier** |
| **Cycle de vie badge** | Badge détruit/recréé | Badge physique réutilisable (`bound` -> `lapsed` -> `revalidated` ou `released`) | **Créer** |
| **Paywall & Paiements** | Aucun paywall de licence | Paywall automatique à expiration d'essai, déclaration de paiement | **Créer** |

---

## 3. Éléments devenus obsolètes à retirer ou adapter

1. **Numérotation automatique par compteur à l'inscription** : `gym_counters`, `next_member_number()`, `reserve_member_numbers()`, numéros `TMP-xxxx`. Le numéro de membre est désormais hérité du numéro du badge physique scanné lors de l'activation.
2. **QR style par membre** : `members.qr_style` n'a plus de raison d'être (le style est uniforme par modèle de salle).
3. **Formulaire d'inscription directe sans carte** : Remplacé par le flux en 4 étapes "Activer une carte".
4. **Carte membre nominative avec photo** : Supprimée au profit du badge anonyme d'impression par lots.
5. **Rôle `manager`** : Supprimé de toutes les contraintes, RLS, fonctions, DTOs et interfaces au profit de `supervisor`.

---

## 4. Risques de migration & Mitigations

1. **Cartes existantes déjà imprimées (V1)** :
   - *Risque* : Des membres ont déjà des cartes V1 avec un QR format `GD1|<gym>|<number>|<token>`.
   - *Mitigation* : Le script de migration `08_v2_migration.sql` crée rétroactivement un lot `plan_allotment` et des badges `bound` reprenant les anciens `qr_token` et numéros. Le scanner accepte les payloads `GD1` et `GD2`.
2. **Absence de PIN pour les membres existants** :
   - *Risque* : Les anciens membres n'ont pas de PIN dans `member_pins`.
   - *Mitigation* : Initialiser les lignes `member_pins` avec `reset_required = true`. Au premier scan, le scanner indique "PIN non défini, voir la réception", permettant une définition fluide du code.
3. **Appareils hors ligne avec synchronisation en cours** :
   - *Risque* : Décalage de version de schéma et opérations outbox pendant la bascule.
   - *Mitigation* : Versionnement Drift (`schemaVersion = 2`) avec `onUpgrade` non destructif et rétrocompatibilité des colonnes dans `sync_push`.
4. **Tricherie sur l'horloge de l'appareil pour contourner l'essai** :
   - *Risque* : Reculer la date de la tablette pour prolonger les 7 jours d'essai.
   - *Mitigation* : La date `trial_ends_at` est calculée par le serveur (`now() + 7 days`). Le client s'appuie sur le bail de licence signé et sur `ClockGuard`. Si l'horloge recule ou si le bail expire, l'application bloque le scan.

---

## 5. Plan d'exécution ordonné (Phases B & C)

1. **Migration SQL et Drift (`08_v2_migration.sql`, Drift schema v2)** : Nouvelles tables, contraintes, renommage `manager` -> `supervisor`, rétro-migration des badges et membres.
2. **Edge Function & Fonctions Serveur** : `create_gym_with_owner`, `gym_access_state`, `generate_badge_batch`, RPCs de cycle de vie de badges et vérification/réinitialisation de PIN.
3. **Onboarding & Authentification V2** : Écrans d'onboarding (4 étapes), stockage sécurisé du statut vu, refonte login/création de compte, assistant de création de salle en 4 étapes.
4. **Abonnement SaaS & Paywall** : Cartes des offres avec curseur dynamique et comparateur, bandeau d'essai, paywall de blocage, formulaire "J'ai payé" (`payment_declarations`), validation super admin.
5. **Gestion des Badges par Lots** : Écran Badges, gestion des quotas selon l'offre, génération de lots, template CR80 anonyme sans nom/photo, exports PDF (planche A4 & unitaire) et ZIP PNG 300 dpi.
6. **Activation de Carte & Abonnements Membres** : Assistant d'activation en 4 étapes (Scan carte vierge -> Infos membre -> Formule & Paiement -> PIN membre), cycle de vie du badge (`bound`, `lapsed`, `released`, `blocked`, `replaced`), validation superviseur des renouvellements.
7. **Code PIN Membre** : Chiffrement salé PBKDF2/Argon2id, règles anti-triviaux, test de mémorisation en 3 étapes, vérification hors ligne dans Drift sécurisé, blocage après échecs.
8. **Scanner Kiosque Verrouillé** : Verrouillage persistant, canal Android/Windows, pavé numérique de PIN membre plein écran (option d'ordre aléatoire des touches), déverrouillage sécurisé superviseur/owner hors ligne et en ligne.
9. **Nettoyage de l'obsolète & Finalisation** : Nettoyage du code V1 obsolète, traductions complètes (Créole, Français, Anglais), tests unitaires et d'intégration, documentation README.

# GymDesk

Gestion multi-salles de sport pour Android, Windows et Web. Architecture Flutter / Supabase, locale en priorité, interface en créole haïtien, français et anglais.

## État réel du projet

Le projet est en cours de construction. Il ne constitue pas encore une application de gestion complète ni une version validée pour la production.

Sources présentes :

- Schéma PostgreSQL, fonctions métier, RLS, Storage privé, amorçage administrateur et seed de test.
- Correctif SQL `07_sync.sql` : isolation des références entre salles, restrictions des fonctions, contrôle des identités, blocage des salles suspendues, RPC de synchronisation et reçus idempotents.
- Entrée Flutter, configuration externe, thème blanc avec accent de salle, navigation responsive, traductions des écrans livrés.
- Connexion Supabase, persistance sécurisée de session, restauration d’un contexte de personnel précédemment vérifié, expiration de l’autorisation hors ligne, déconnexion pour inactivité.
- Miroir local Drift, outbox transactionnelle, réservation de numéros, file de photos, stockage des conflits.
- Push séquentiel, reprise avec temporisation, pull paginé, déclenchement périodique et Realtime, état de synchronisation affiché.
- Écrans de connexion, inventaire des données locales, détails de synchronisation et paramètres de langue/session. L’inventaire local n’est pas le futur tableau de bord métier.
- Administration plateforme : liste paginée des salles, statistiques agrégées, création de salle et propriétaire, suspension/réactivation, archivage logique avec confirmation et concurrence optimiste.
- Edge Function `create_gym_owner`, journal de provisionnement reprenable sans mots de passe persistés, demande de réinitialisation du propriétaire et écran de changement du mot de passe via session de récupération.
- Paramètres de salle réservés au propriétaire : identité, couleur, fuseau, devise, pied de page PDF, règles d’accès, scanner, durée offline et PIN ; écriture dans l’outbox via `sync_branding`.
- Upload de logo vers `gym-assets/<gym_id>/logos/`, URL signée pour l’aperçu et validation serveur de l’existence et du dossier de l’objet.
- Gestion du personnel : création de comptes `supervisor`/`reception` par Edge Function, reprise de demande sans mot de passe persisté, modification de profil, rôle et activation par le propriétaire.
- Verrouillage PIN local : PBKDF2 dans un stockage sécurisé, verrouillage au démarrage ou après inactivité, cooldown progressif, blocage après dix échecs, réinitialisation par nouvelle connexion mot de passe. Le PIN ne remplace pas Auth et ne change jamais de rôle.
- Gestion des plans : création/modification locale, activation, archivage propriétaire et validations bornées.
- Gestion des membres : liste, recherche, filtres de validité, fiche, création/modification hors ligne, photo JPEG normalisée et mise en file, NIF/CIN, contact d’urgence et responsable légal mineur.
- Détection locale de doublons probables par NIF, téléphone/WhatsApp ou nom + date de naissance ; les contraintes SQL restent l’autorité finale.
- Inscription transactionnelle : membre, photo, abonnement et paiement initial partagent la même transaction locale ; les numéros réservés ou `TMP-*` sont traités par le protocole de synchronisation existant.
- Abonnements et paiements : création, renouvellement à la fin du cycle courant, paiement partiel, encaissement du solde, annulation réservée aux propriétaires/superviseurs, historique et écran de caisse.
- Scanner d’accès : QR `GD1|code|numéro|token`, caméra selon la plateforme ou scanner USB, résultat local immédiat, observations append-only, protection anti-doublon et validation serveur du jeton, de la validité et du numéro d’entrée.
- Cartes de membre : modèles synchronisés avec un seul défaut, orientation paysage/portrait, options photo/QR/statut, aperçu local, export PDF et impression système.
- Tableau de bord : membres actifs, abonnements proches de la fin, entrées/refus du jour, encaissements et soldes en attente, calculés sur la base locale.
- Rapports : période du jour/7/30 jours, paiements, présences, expirations, audit propriétaire, export PDF et copie CSV.
- Audit : actions serveur détaillées (création, renouvellement, annulation, scan, régénération QR, badges), lecture réservée au propriétaire par RLS.
- Tests Dart, Deno et assertions SQL écrits.

La clôture de caisse formelle et les derniers réglages de production restent à traiter. Aucun écran simulant ces fonctionnalités n’est présenté.

**Vérification actuelle :** `flutter pub get`, `dart run build_runner build`, `dart fix --apply`, `dart format lib test web/drift_worker.dart`, `flutter analyze` et `flutter test` ont été exécutés avec le SDK local `.tools/flutter` : aucun problème d’analyse et 58/58 tests Dart réussis. `deno check` et `deno test` ont aussi réussi pour les deux Edge Functions. `flutter build apk --debug` a produit `build/app/outputs/flutter-apk/app-debug.apk`. Les tests PostgreSQL/Supabase, les essais réseau réels et les builds Windows/Web ne sont pas encore validés.

## 0. Fonctionnement V2

La V2 transforme GymDesk en SaaS self-service avec cartes anonymes :

- **Inscription en libre-service** : au premier lancement, l’écran d’onboarding (4 pages) mène vers `/signup`. L’assistant en 4 étapes (salle → propriétaire → offre → récapitulatif) appelle l’Edge Function `create_gym_with_owner`, qui crée la salle en statut `trial`, le compte propriétaire, le contrat, 5 plans par défaut et un lot de 10 badges d’essai. Le même e-mail ou téléphone ne peut pas créer un second essai.
- **Essai de 7 jours** : les dates `trial_started_at`/`trial_ends_at` sont fixées par le serveur ; l’horloge de l’appareil ne peut pas prolonger l’essai (`ClockGuard` + `gym_access_state`). À l’expiration, `cron_suspend_expired_trials` passe la salle en `suspended` et l’application affiche le paywall `/paywall` pour tous les rôles ; l’export des données reste disponible. Le propriétaire déclare son paiement (`payment_declarations`) ; un super admin le valide via `review_payment_declaration`, ce qui réactive la salle sans réinstallation, en ligne ou au prochain contact réseau.
- **Badges anonymes par lots** : les cartes CR80 ne montrent ni nom ni photo — logo, nom et téléphone de la salle, grand QR (`GD2|code|numéro|token`), numéro de badge. Numérotation `01`…`99` puis 3 chiffres, jamais réutilisée. Quotas : 10 en essai, sinon `price_snapshot.config.badge_quota` du contrat synchronisé ; le serveur refuse tout dépassement (`badge_quota_exceeded`). Génération par `generate_badge_batch`, badges supplémentaires via `request_extra_badges` puis validation admin.
- **Activation** : un badge vierge scanné ouvre l’assistant `/activate` (carte → membre → abonnement/paiement → PIN avec test de mémorisation). Hors ligne, tout part dans l’outbox ; en ligne, le serveur arbitre les activations concurrentes (premier arrivé gagne, conflit `sync_push`).
- **PIN membre** : 4 à 6 chiffres, anti-triviaux (répétitions, suites, année de naissance) validés par `validateMemberPinFormat`. Empreinte PBKDF2-SHA256 salée (210 000 itérations) dans `member_pins` — jamais en clair, jamais dans les journaux ni les exports. 5 échecs consécutifs = blocage 5 min ; 10 échecs cumulés = réinitialisation requise par owner/supervisor (`reset_member_pin`). Les membres V1 migrés ont `pin_hash='UNSET'` et définissent leur code à la réception.
- **Scanner** : `resolveBadge` distingue badge inconnu, d’une autre salle, non activé, bloqué ou lié ; aucune info membre n’est révélée avant le PIN correct. Le jeton QR brut n’est jamais stocké dans `attendance`. Les formats `GD1` (cartes déjà imprimées) et `GD2` sont acceptés.
- **Kiosque** : « Verrouiller le scanner » confine l’application à `/kiosk` (retour, menus et raccourcis bloqués, état persistant après redémarrage, `startLockTask` sur Android). Déverrouillage uniquement par e-mail + mot de passe owner/supervisor, hors ligne possible via l’empreinte sécurisée stockée ; 5 échecs = 5 min de cooldown ; tout est audité.
- **Rôles** : `manager` est remplacé par `supervisor` (base, API, UI). Les renouvellements saisis par la réception restent `pending` jusqu’à validation owner/supervisor (`/subscriptions/renewals`).
- **Migration** : `08_v2_migration.sql` crée rétroactivement badges liés et lignes `member_pins` pour les membres V1 sans perte de données ; le schéma Drift passe en v2 par migration non destructive. `13_v2_sync.sql` étend `sync_push`/`sync_pull` aux entités V2 et ajoute `platform_invoices`.

### Installation tablette (Android)

1. Construire l’APK : `%FLUTTER% build apk --release` (ou `--debug` pour le test).
2. Copier `build/app/outputs/flutter-apk/app-release.apk` sur la tablette et l’installer.
3. Premier démarrage : onboarding → *Créer ma salle* (ou connexion d’un compte existant).
4. Sur la page Scanner, un owner/supervisor appuie sur « Verrouiller le scanner » pour passer en mode kiosque ; sur Android, l’épinglage d’écran (lock-task) se combine avec le mode kiosque système de la tablette.

### Impression des badges

- Page **Cartes** (`/badges`, owner/supervisor) : générer un lot, puis « Exporter la planche A4 » ou imprimer une carte individuelle depuis la fiche membre (`/members/:id/badge`).
- Les PDF sont au format CR80 (85,6 × 54 mm) avec repères de coupe optionnels ; imprimer à 100 % sans mise à l’échelle et vérifier la lisibilité du QR avant la série.

### Création de salle

- **Self-service** : écran d’inscription (`/signup`) → essai 7 jours automatique.
- **Super admin** : page Salles (`/gyms/new`) comme en V1.

## 1. Prérequis de vérification et de build

- Flutter stable 3.47.6 / Dart 3.13.5 installés localement sous `.tools/flutter`.
- Deno 2.9.7 installé localement sous `.tools/deno`.
- Supabase CLI 2.x et un projet Supabase de développement, ou Supabase local avec Docker.
- Android SDK pour Android ; Visual Studio avec les outils C++ pour Windows.
- Navigateur récent et HTTPS pour le déploiement Web.

Les outils sont volontairement locaux au projet : ils ne modifient pas le `PATH` global. Sous Windows, depuis `gym_desk` :

```bat
set "FLUTTER=%CD%\.tools\flutter\bin\flutter.bat"
set "DART=%CD%\.tools\flutter\bin\cache\dart-sdk\bin\dart.exe"
set "DENO=%CD%\.tools\deno\deno.exe"
```

Les dépendances directes sont fixées dans `pubspec.yaml` à des versions publiées depuis plus de sept jours au moment de leur sélection. `pubspec.lock` est maintenant produit et versionné.

`drift_flutter` 0.3.1 utilise SQLite via le mécanisme actuel du package `sqlite3`. `sqlite3_flutter_libs` est désormais publié comme package de fin de vie ; il n’est pas ajouté comme dépendance directe supplémentaire.

## 2. Base Supabase

Exécuter une seule fois, sur une base de développement neuve, dans cet ordre :

```text
supabase/sql/01_schema.sql
supabase/sql/02_functions.sql
supabase/sql/03_rls.sql
supabase/sql/04_storage.sql
supabase/sql/05_admin.sql
supabase/sql/06_seed.sql        optionnel, test uniquement
supabase/sql/07_sync.sql        correctifs et protocole de synchronisation
supabase/sql/08_platform.sql    administration et provisionnement des salles
supabase/sql/09_settings_staff.sql  branding, paramètres et personnel
supabase/sql/10_attendance.sql    validation serveur des scans
supabase/sql/11_audit.sql         actions d’audit détaillées
supabase/sql/08_v2_migration.sql  schéma V2 (essais, badges, PIN, déclarations) — idempotent
supabase/sql/12_v2_functions.sql  fonctions V2 (accès, lots, PIN, contrat)
supabase/sql/13_v2_sync.sql       synchronisation et RPC V2 complémentaires
```

`05_admin.sql` exige de modifier l’email indiqué et de créer d’abord le compte correspondant dans Supabase Auth. Ne jamais placer son mot de passe dans un script versionné.

Si les scripts 01–06 ont déjà été exécutés, appliquer 07 puis 08 puis 09 puis 10 puis 11 ; si 07, 08 et 09 sont déjà installés, appliquer seulement 10 puis 11. Pour passer une base V1 existante en V2, exécuter ensuite `08_v2_migration.sql`, `12_v2_functions.sql` puis `13_v2_sync.sql` dans cet ordre ; ces scripts V2 sont idempotents et rejouables sans perte de données. Les correctifs 07–11 sont transactionnels mais ne sont pas destinés à être rejoués. Ne pas rejouer les scripts précédents après leurs correctifs : cela rétablirait des définitions obsolètes. Vérifier au préalable les éventuelles données existantes qui ne respecteraient pas les nouvelles contraintes inter-salles, le format du NIF ou l’unicité d’un propriétaire non supprimé par salle.

Les scripts 01–06 seuls ne suffisent pas pour cette livraison. Ils contenaient notamment des fonctions trop permissives et un contrôle incomplet des salles suspendues ; 07 remplace les définitions concernées.

Pour utiliser les migrations Supabase CLI, transformer les scripts en migrations horodatées, en conservant leur ordre. Les fichiers placés seulement dans `supabase/sql` ne sont pas automatiquement exécutés par `supabase db push`.

### Tests SQL

Exécuter `supabase/tests/sync_security_tests.sql` comme administrateur SQL sur une instance de développement jetable après installation du schéma et du correctif 07. Le script crée ses propres utilisateurs et salles dans une transaction, vérifie les politiques avec le rôle `authenticated`, puis effectue un `ROLLBACK`. Il n’exige aucun UUID à éditer ni le seed 06.

Il vérifie notamment : lecture/écriture entre salles, clés étrangères composites, allocation de numéros, relecture d’une opération, présences append-only, paiements de réception limités au jour courant, paiements offline anciens, auto-promotion interdite et suspension d’une salle.

Après 08, exécuter `supabase/tests/platform_tests.sql`. Après 09, exécuter `supabase/tests/settings_staff_tests.sql` : il couvre le rejeu de provisionnement du personnel, l’absence de mot de passe dans `staff_provisioning`, la validation du branding et du logo, la version optimiste, les clés de paramètres autorisées, la modification d’accès et le refus d’écriture `gym-assets` pour un manager. Exécuter également `supabase/tests/member_tests.sql` pour l’isolation des membres, les rôles de plans/abonnements/paiements, l’unicité NIF et `member_validity`. Après 10, exécuter `supabase/tests/attendance_tests.sql` pour l’autorité serveur sur le token QR, la validité, l’anti-doublon, `scanned_by` et l’append-only. `supabase/tests/badge_tests.sql` vérifie les rôles des modèles de carte et l’unicité du modèle par défaut. Après 11, `supabase/tests/audit_tests.sql` vérifie la liste blanche d’actions, les détails JSON et la lecture audit réservée au propriétaire.

Le fichier historique `rls_tests.sql` est un guide manuel avec des paramètres à remplacer, pas une suite automatisée. Utiliser les nouveaux scripts pour les assertions autonomes.

## 3. Préparer les cibles et générer le code

Les plateformes Android, Windows et Web sont maintenant générées. Pour régénérer uniquement si une cible manque :

```bat
%FLUTTER% create --platforms=android,windows,web --project-name gym_desk .
%FLUTTER% pub get
%DART% run build_runner build
```

Ne pas utiliser `--overwrite` : conserver les sources applicatives existantes. Examiner les changements des fichiers racine créés par `flutter create`. Les fichiers `.g.dart` sont générés à partir des annotations Riverpod, de `local_database.dart` et du schéma `local_database.drift` ; ils ne doivent pas être écrits manuellement.

Sur Windows, activer le mode développeur pour permettre les liens symboliques requis par certains plugins avant `flutter build windows`. Visual Studio avec la charge « Desktop development with C++ » reste nécessaire.

### Web : SQLite et worker

Le code source du worker est fourni :

```bat
%DART% compile js -O4 web\drift_worker.dart -o web\drift_worker.dart.js
```

Récupérer `sqlite3.wasm` correspondant exactement à la version Drift verrouillée dans `pubspec.lock`, depuis les releases officielles : https://github.com/simolus3/drift/releases . Le placer dans `web/sqlite3.wasm` avant le build Web. Le worker et le WASM doivent rester compatibles avec Drift.

Le serveur doit servir `.wasm` avec `Content-Type: application/wasm`. Configurer également :

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

L’application refuse les modes de stockage Drift `inMemory` et `unsafeIndexedDb` pour éviter de présenter comme persistantes des opérations qui pourraient être perdues. Ne pas utiliser la navigation privée. Le fonctionnement hors ligne après fermeture complète du navigateur exige aussi une stratégie de cache des ressources Web à vérifier lors du déploiement ; SQLite seul ne rend pas le chargement de l’application disponible hors ligne.

## 4. Configuration sans secrets embarqués

Fournir l’URL du projet et sa clé publique `anon` ou `publishable` :

```bat
%FLUTTER% run --dart-define=SUPABASE_URL=https://VOTRE-PROJET.supabase.co --dart-define=SUPABASE_ANON_KEY=VOTRE_CLE_PUBLIQUE
```

Ces noms sont des paramètres à remplacer, pas des identifiants fournis. L’application affiche une explication si la configuration est absente. HTTPS est requis, sauf pour un serveur HTTP sur `localhost` ou `127.0.0.1`.

Ne jamais intégrer une clé `service_role` ou une clé secrète Supabase au binaire. Les comptes de personnel doivent exister dans `auth.users` et posséder une ligne active correspondante dans `public.staff`.

Le compte super administrateur est orienté vers l’écran Salles. Il ne télécharge pas les données personnelles des membres. La lecture des statistiques passe par une RPC qui ne retourne que quatre compteurs globaux. L’administration plateforme exige le réseau, contrairement aux opérations de réception destinées à fonctionner hors ligne.

## 5. Contrat local et synchronisation

### Stockage

Le fichier SQLite est séparé par projet Supabase, salle, utilisateur et rôle. Le miroir `records` conserve le document complet de chaque ligne, son UUID, sa salle, sa version serveur et sa suppression logique. Des index portent sur l’entité, la salle, le nom, le jeton QR et les abonnements par membre. Ce n’est pas une seconde copie relationnelle du schéma PostgreSQL : les relations inter-salles sont imposées sur le serveur.

Les tables locales techniques sont `outbox`, `sync_metadata`, `number_blocks`, `photo_uploads` et `sync_conflicts`.

L’écriture du document et de son opération outbox est atomique. L’inscription d’un membre consomme son numéro, écrit la fiche, met la photo en file et ajoute l’abonnement/paiement éventuels dans une même transaction locale. Un acquittement serveur ne remplace pas une modification locale survenue pendant la requête. Les suppressions métier utilisent des tombstones.

Les photos JPEG sont conservées durablement comme blobs dans une file SQLite séparée, compatible avec le Web, et envoyées vers un chemin versionné `gym_id/member_id/upload_id.jpg`. Le formulaire membre normalise localement la photo en JPEG avant sa mise en file. Aucun téléchargement de photo n’est réalisé dans le thread de saisie.

### Protocole

- `sync_context` vérifie personnel, salle et heure serveur avant chaque cycle.
- `sync_push` vérifie l’isolation et utilise un UUID d’opération stable. Mutation et reçu sont enregistrés dans la même transaction. Un renvoi de présence ne fait pas d’UPDATE.
- Pour une ligne modifiable, la version de base est comparée à la version serveur. En cas de divergence, l’horodatage de modification transmis est comparé au `updated_at` serveur ; le conflit est audité sans copie de données personnelles dans le journal.
- Les tentatives temporaires utilisent un backoff exponentiel borné. Une erreur permanente bloque les opérations suivantes, sans effacer la file ; le pull peut continuer pour recevoir notamment les suspensions et modifications récentes.
- `sync_pull` utilise une pagination par couple horodatage/UUID, une borne haute serveur et un recouvrement de dix minutes. Les présences utilisent `server_received_at`, pas l’horloge du scan.
- Une réconciliation complète est demandée au démarrage, au bouton manuel et au moins quotidiennement. Elle couvre notamment les transactions dont le commit tardif pourrait dépasser la fenêtre incrémentale. Ce protocole assure une convergence, pas un snapshot global instantané entre toutes les pages.
- Un cycle périodique intervient toutes les 60 secondes. Le retour réseau et les événements Realtime déclenchent aussi une tentative. La présence d’une interface réseau n’est pas considérée comme la preuve que Supabase est joignable.
- Le correctif SQL ajoute les tables à la publication `supabase_realtime` si celle-ci existe ; vérifier l’activation de Realtime sur l’instance cible.

La file outbox et les conflits ne contiennent jamais les messages d’erreur bruts de PostgreSQL : seuls des codes contrôlés sont affichés. Les charges utiles métier locales restent sensibles et doivent être protégées par la sécurité de l’appareil.

### Autorisation offline et horloge

Le contexte mis en cache autorise par défaut 24 heures hors ligne, réglables entre 1 et 72 heures avec `settings.offline_lease_hours`. Le téléchargement initial doit être terminé. Une salle suspendue ou un compte révoqué bloque l’accès dès que le serveur l’annonce.

Une suspension distante ne peut pas être connue immédiatement par un appareil totalement déconnecté. Le délai offline limite cette fenêtre ; ne pas promettre une révocation instantanée sans réseau.

`settings.auto_logout_minutes` vaut 30 par défaut ; 0 désactive la déconnexion automatique. Les opérations non envoyées ne sont pas effacées à la déconnexion. Un changement de rôle isole le nouveau contexte du cache de l’ancien rôle ; les anciennes opérations restent dans l’ancien fichier, sans transfert automatique.

L’horloge est comparée à un chronomètre monotone pendant la session et calibrée avec l’heure du serveur. Un recul ou une dérive de plus de dix minutes marque l’horloge comme suspecte. Cette détection ne constitue pas une protection contre la falsification d’un appareil compromis.

Les sessions utilisent `flutter_secure_storage`. La base métier SQLite n’est pas chiffrée dans ce socle. Sur Web, aucun stockage côté client ne protège contre une XSS ou un utilisateur contrôlant son navigateur. Le PIN ajoute un verrouillage d’interface local : il ne chiffre pas la base, ne réauthentifie pas le poste auprès de Supabase et ne remplace pas une session révoquée côté serveur.

## 6. Langues et thème

Les textes des écrans livrés sont traduits dans `lib/l10n/app_strings.dart`, avec `ht` par défaut. Les libellés système Material/Cupertino utilisent temporairement le français quand la langue est `ht`, faute de délégation créole fournie par Flutter. Une traduction des contrôles système reste nécessaire pour une interface intégralement créole.

Le thème applique la couleur de la salle et conserve les fonds blancs. Les polices DM Sans et Syne utilisent actuellement `google_fonts` ; elles devront être embarquées comme assets avec leurs licences avant distribution pour garantir leur disponibilité dès un démarrage sans réseau.

## 7. Vérifications

```bat
%DART% run build_runner build
%DART% format lib test web\drift_worker.dart
%FLUTTER% analyze
%FLUTTER% test
%DENO% check supabase\functions\create_gym_owner\index.ts
%DENO% check supabase\functions\manage_staff\index.ts
%DENO% test supabase\functions\create_gym_owner\handler_test.ts
%DENO% test supabase\functions\manage_staff\handler_test.ts
```

Suites exécutées : transactions locales, isolation, numérotation et TMP, append-only, conflits, protection des modifications concurrentes, retry idempotent, suspension de salle, synchronisation unique en vol, dérive d’horloge, localisation, base de version du branding, comportement du PIN (cooldown, blocage, retrait et réinitialisation après mot de passe), normalisation NIF/téléphone, validité des abonnements, transaction d’inscription membre, photo en file, doublons, renouvellement/encaissement, scans hors ligne/anti-doublon, modèles de badges, tableau de bord et agrégation des rapports.

Ajouter ensuite les tests métier de rendu QR, scan, exports et les essais multi-appareils, puis mesurer les objectifs de performance sur les appareils cibles. Aucun objectif de performance n’a encore été mesuré. Les scripts SQL de test n’ont pas encore été exécutés sur PostgreSQL/Supabase.

## 8. Builds et déploiement ultérieurs

Après résolution des dépendances, génération, tests et configuration des plateformes :

```bat
%FLUTTER% build apk --release --dart-define=SUPABASE_URL=VOTRE_URL --dart-define=SUPABASE_ANON_KEY=VOTRE_CLE_PUBLIQUE
%FLUTTER% build windows --release --dart-define=SUPABASE_URL=VOTRE_URL --dart-define=SUPABASE_ANON_KEY=VOTRE_CLE_PUBLIQUE
%FLUTTER% build web --release --dart-define=SUPABASE_URL=VOTRE_URL --dart-define=SUPABASE_ANON_KEY=VOTRE_CLE_PUBLIQUE
```

Préparer la signature Android hors du dépôt, empaqueter le dossier Windows produit par la version Flutter utilisée, et héberger `build/web` avec les règles de sécurité et de routage adéquates. Aucun APK n’est fourni à ce stade.

## 9. Déployer l’administration plateforme

Appliquer le script 08 après 07. L’Edge Function utilise `fetch` et les API REST/Auth de Supabase sans dépendance JavaScript tierce. Elle vérifie le jeton auprès de Supabase Auth, puis le rôle actif `super_admin` en base ; elle ne se fie pas à un rôle transmis par le navigateur.

Variables de l’Edge Function :

- `SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY` : variables serveur fournies par Supabase. Jamais de copie dans Flutter.
- `GYMDESK_ALLOWED_ORIGINS` : liste séparée par des virgules des origines Web exactes autorisées. Aucun wildcard. Les clients Android/Windows sans en-tête Origin utilisent toujours une session authentifiée.
- `GYMDESK_PASSWORD_RESET_REDIRECT` : URL HTTPS du déploiement Web, terminée par `/reset-password`. Ajouter cette URL à la liste des redirections autorisées de Supabase Auth. Le serveur Web doit renvoyer l’application sur cette route.

Configurer ces valeurs dans les paramètres des Edge Functions et déployer :

```sh
supabase functions deploy create_gym_owner
supabase functions deploy manage_staff
```

Ne pas désactiver les contrôles du JWT de la passerelle pour masquer une erreur de configuration. Configurer un service SMTP adapté dans Supabase Auth et tester les liens de récupération sur le déploiement cible. Un retour HTTP accepté ne garantit pas que l’email a effectivement été livré.

### Créer une salle

1. Se connecter avec le super administrateur préparé par `05_admin.sql`.
2. Ouvrir **Salles → Nouvelle salle**.
3. Saisir le nom, le code de 3–4 lettres, la couleur, le fuseau IANA, la devise et les coordonnées.
4. Saisir le nom, un email non encore utilisé dans Auth et un mot de passe initial de 12–128 caractères pour le propriétaire.
5. Confirmer la création. Transmettre le mot de passe initial par un canal sécurisé ; le compte est créé par l’administrateur avec l’email confirmé. Ce processus suppose que l’administrateur a vérifié l’identité du propriétaire.
6. Le propriétaire peut se connecter et réaliser son téléchargement initial. Les modules métier se raccordent ensuite à ce contexte de salle.

Le logo n’est pas saisi dans le formulaire de création de salle ; le propriétaire le téléverse ensuite dans **Paramètres → Identité et image**, en ligne uniquement.

### Reprise après interruption

Les UUID de demande, de salle et de personnel sont générés côté Flutter. Le brouillon de provisionnement est conservé dans le stockage sécurisé, **sans mot de passe**, par projet et administrateur. Réouvrir Nouvelle salle reprend le même brouillon ; ne pas générer une nouvelle demande pour contourner un délai réseau.

La création Auth et la transaction PostgreSQL ne constituent pas une transaction distribuée. Le compte Auth reçoit une métadonnée administrative immuable de rattachement à la demande. Si le compte existe mais que la transaction de salle a échoué, la même demande retrouve ce compte et termine l’opération, sans rattacher un compte préexistant appartenant à quelqu’un d’autre. Avant la création du personnel, ce compte ne bénéficie d’aucun droit de salle.

La table technique `gym_provisioning` est inaccessible aux clients authentifiés ; seules les RPC du rôle serveur peuvent la gérer. Une demande pendante réserve son code. En cas de conflit externe persistant, faire examiner la demande par un administrateur de base plutôt que de supprimer automatiquement un compte Auth ou de modifier son rattachement. Aucun nettoyage destructif automatique n’est effectué.

### Personnel et PIN

La création d’un compte `manager` ou `reception` exige le rôle `owner` de la salle et une session en ligne. Le brouillon `staff_provisioning` permet de reprendre la même demande après une interruption réseau ; le mot de passe n’est jamais stocké. La modification du nom/téléphone est une écriture directe en ligne sur `staff`, limitée par RLS. Le changement de rôle ou d’activation passe par `update_staff_access`, exige la version locale `updated_at` et se fait en ligne uniquement. Un propriétaire ne peut pas modifier son propre accès, promouvoir quelqu’un en propriétaire ni déplacer un membre vers une autre salle.

Le verrouillage PIN est par utilisateur local et par projet Supabase. Le délai `pin_lock_minutes` verrouille l’interface, tandis que `auto_logout_minutes` ferme la session locale. Sur Web ou lorsque le stockage sécurisé n’est pas disponible, `unlock()` est rejeté proprement plutôt que d’ouvrir la session.

### Suspension, archivage et récupération

Suspension et réactivation exigent une confirmation. Les RPC comparent `updated_at` avec la version affichée ; en cas de modification concurrente, l’interface recharge les données. L’archivage exige de saisir le code de la salle et conserve les historiques ; il ne supprime ni les membres ni les présences.

Le bouton de réinitialisation envoie une demande d’email au propriétaire actif. Cette demande est auditée et limitée à une par minute et par salle. La page `/reset-password` est accessible via une session de récupération. Au démarrage Web, le contexte de récupération est reconnu seulement si le jeton du lien correspond à celui de la session récupérée, pour éviter de réinitialiser par erreur un autre compte déjà connecté. Après modification du mot de passe, la session locale est fermée.

### Tests de ce volet

Après 08, exécuter `supabase/tests/platform_tests.sql` sur une instance de développement jetable. Les fixtures sont annulées à la fin. Les assertions couvrent notamment le rejeu du provisionnement, les privilèges des RPC, les statistiques, la concurrence et l’archivage.

Avec Deno disponible :

```bat
%DENO% check supabase\functions\create_gym_owner\index.ts
%DENO% check supabase\functions\manage_staff\index.ts
%DENO% test supabase\functions\create_gym_owner\handler_test.ts
%DENO% test supabase\functions\manage_staff\handler_test.ts
```

Les tests du handler utilisent un service simulé uniquement dans la suite de tests, sans créer de compte ni envoyer d’email. Les tests d’intégration réels Auth/REST/SMTP et le parcours de récupération complet restent à exécuter avant déploiement.

Designed by Cvisual

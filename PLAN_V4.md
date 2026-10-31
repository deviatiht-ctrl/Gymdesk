# PLAN V4 — Rangement SecurGYM (suivi pour reprise par une autre IA)

Demande originale (créole) résumée en exigences. Chaque item a un statut :
`[ ]` à faire · `[~]` en cours / partiel · `[x]` fait (avec fichiers touchés).
Mettre à jour ce fichier à chaque étape terminée. Vérification : voir `AGENTS.md`
(`flutter analyze --no-pub`, `flutter test --no-pub` depuis `gym_desk/`).

## Phase 1 — Bugs & accès (priorité haute, pas de SQL)
- [x] 1.1 Badge « Aucun abonnement » pour membres fraîchement inscrits alors que l'abonnement est actif.
      Cause : `GymSubscription.startDate/endDate` = `DateTime.parse('YYYY-MM-DD')` → minuit LOCAL,
      comparé à `gymDate()` (UTC) ⇒ en Haïti (UTC-4/-5) un abonnement qui commence aujourd'hui paraît futur.
      Fix : parser en `DateTime.utc(y,m,d)` (`lib/features/subscriptions/domain/gym_subscription.dart`).
- [x] 1.2 Interface membres affiche du créole en dur alors que l'app est en français
      (`members_page.dart` boutons/filtres, `fingerprint_transfer_dialog.dart`, etc.) → passer par `AppStrings`.
- [x] 1.3 Employés : quand ils scannent l'empreinte, leur NOM doit s'afficher normalement
      (door_access_page ignorait les décisions employé ; overlay affichait message « abonnement »).
- [x] 1.4 Au scan : afficher « Accès autorisé » + NOMBRE DE JOURS RESTANTS partout
      (overlay global, page Contrôle d'accès, tablette).
- [x] 1.5 App épinglée (SecurGYM.exe lancé directement) : rien ne marche sans `Lancer_SecurGYM.bat`.
      Fix : au démarrage Windows, si `http://127.0.0.1:47811/health` ne répond pas, l'app lance elle-même
      `access_agent.exe` (cherché à côté de l'exe, puis dossier parent) en mode détaché.
- [x] 1.6 Contrôle d'accès doit fonctionner même si on n'est pas sur la page : watcher terminal global
      (service unique au niveau du shell, Windows seulement) → popups partout + IP lecteur auto.
- [x] 1.7 Tablette lente : afficher immédiatement depuis le snapshot realtime (pas de re-requête lourde).
- [x] 1.8 Anciennes empreintes BioStar : on les laisse ; elles expirent avec l'abonnement, on ré-enrôle sur le nouveau système. (Aucun code.)

## Phase 2 — Devises USD / HTG (très important)
- [x] 2.1 Réglage gym : devise de base (USD) + taux du jour HTG/USD (settings `exchange_rate_htg`).
- [x] 2.2 Encaissement : choisir la devise payée (USD ou HTG) ; montant dû converti ; « quantité donnée »
      saisie dans la devise payée ; monnaie rendue calculée. Enregistrer `paid_currency`, `exchange_rate`,
      `paid_amount` (dans la devise donnée) en plus de `amount` (devise du plan).
      SQL : nouvelle migration `27_payment_currency.sql` (colonnes nullable, idempotent).
- [x] 2.3 Rapports / caisse : totaux réellement encaissés PAR devise (USD et HTG séparés) + équivalent.

## Phase 3 — Reçus
- [x] 3.1 Page « Reçus » : tous les reçus (y compris anciens membres), recherche par nom / numéro / téléphone,
      re-envoyer (email/WhatsApp), télécharger PDF, imprimer. Caissier : lecture seule (pas modifier/supprimer).
- [x] 3.2 Beau design PDF (déjà `receipt_pdf.dart`) ; WhatsApp : envoyer le lien PDF signé + message propre.
- [~] 3.3 Vérifier pourquoi l'email reçu ne part pas (queue `enqueue_payment_receipt`, upload storage).

## Phase 4 — Page Paiements
- [x] 4.1 Filtres par période (jour / mois / année / plage) + totaux par devise.
- [x] 4.2 Clic sur un paiement → fiche détaillée (membre, plan, devise, taux, reçu, encaissé par, monnaie…).

## Phase 5 — Inscription rapide
- [x] 5.1 Email optionnel ; si fourni, l'email de bienvenue/reçu part automatiquement.
- [x] 5.2 Mode « rapide » : 1 écran (prénom, nom, téléphone, plan, paiement) — le reste optionnel/replié.
      (`enrollment_wizard_page.dart` toggle Mode Rapide / Étapes, form complet en 1 écran, caisse, options repliées, auto-skip empreinte).

## Phase 6 — Personnel (staff) vs Employés
- [x] 6.1 Création personnel : infos + POSTE (caissier / secrétaire / superviseur) + cases d'ACCÈS
      (ajouter membre, caisse, paiements, reçus, rapports, plans, contrôle d'accès…).
      Stocké dans `staff.permissions jsonb` (SQL 28) ; le router/menus lisent ces permissions.
- [x] 6.2 Empreinte du propriétaire + du personnel (enrôlée via lecteur USB), visible dans la fiche.
      (`FingerprintEnrollmentDialog.showGeneric`, `StaffRepository.saveFingerprints/clearFingerprints`, RPC `register_staff_fingerprint`).
- [x] 6.3 Ouverture / déverrouillage de l'app par empreinte sur le laptop (écran Unlock : « Scanner »)
      → identifie le staff (1:N matching dans Drift), ouvre la session avec son rôle et permissions (`unlockWithStaff`).
- [x] 6.4 Rapport envoyé par email au propriétaire (bouton + quotidien via outbox `kind=daily_report`).
      (`enqueue_daily_report` RPC, `send_emails` edge function template `daily_report`, bouton sur page Rapports).

## Phase 7 — Portail web membre (securgym.com) en temps réel
- [x] 7.1 Lien/QR par gym (`/join/<gym_code>`) : le membre remplit nom, téléphone, email, choisit le plan (prix).
      Insère dans `portal_requests` (SQL 29, RPC anon `portal_submit`, RPC anon `portal_get_gym`, rate-limit).
- [x] 7.2 Page app « Demandes en attente » (realtime) : caissier/secrétaire confirme paiement + empreinte
      → bouton « Valider & Encaisser » pré-remplit l'assistant `/members/new`, valide l'inscription et passe le statut en `completed`.
- [ ] 7.3 Renouvellement via lien/QR : le membre se présente, met son empreinte (USB ou porte) → la demande
      est liée à son identité ; sans empreinte il ne voit rien. Caissier valide en temps réel.
- [x] 7.4 Espace membre : jours restants, historique, reçus PDF, infos du gym, bouton renouveler (SQL 34, `lib/features/member_portal/`).

## Journal d'avancement
(ajouter une ligne par session : date — ce qui est fait — où reprendre)

- 2026-10-19 — Phase 1 terminée (analyze OK, 83 tests OK).
  * 1.1 `gym_subscription.dart` (`_day` UTC) + test `member_rules_test.dart`; `whatsapp_service.dart` sans `.toLocal()`.
  * 1.2 nouvelles clés `lib/l10n/strings_v5.dart` (branché dans `extra_strings.dart`); `members_page.dart`,
    `member_detail_page.dart`, `fingerprint_enrollment_dialog.dart` sans créole en dur. Liste membres montre « Il reste N jours ».
  * 1.3/1.4/1.6 `lib/core/access_control/access_monitor.dart` (singleton `AccessMonitor.instance`, PC seulement) :
    démarre depuis `AccessPopupOverlay` (shell), surveille le W2, `handleTerminalEvent`, sync W2 toutes les 10 min,
    relance l'agent s'il tombe. `door_access_page.dart` et `access_display_page.dart` consomment `monitor.decisions`
    (plus de watcher par page ⇒ plus de double pulse / double présence). Realtime `source=terminal` ignoré sur le PC
    qui l'a produit. `TerminalAccessService.eventRowFor/snapshotFor/eventTypeFor` (statiques) ; snapshot contient `job_type`.
    Popup global localisé : employé ⇒ « Accès autorisé · Employé / Bon travail », membre ⇒ « Il reste N jours ».
  * 1.5 `lib/core/biometrics/agent_launcher*.dart` (import conditionnel) appelé dans `main.dart` : lance `access_agent.exe`
    (dossier parent de l'exe puis dossier de l'exe) si `127.0.0.1:47811/health` ne répond pas.
  * 1.7 tablette : affichage immédiat depuis `member_snapshot`, photo chargée après (`_loadPhotoById`).
  * Bug trouvé : `syncToTerminal` envoyait chaque personne plusieurs fois (clés alias) → dédoublonné par `person.id`.
  * À tester sur le vrai matériel : app épinglée sans .bat, popups sur toutes les pages, tablette.
  * Prochaine étape : Phase 2 (devises).

- 2026-10-19 (suite) — Phases 2, 3, 4 faites + 5.1 (analyze OK).
  * SQL `supabase/sql/27_currency_exchange.sql` (À APPLIQUER après 26) : `payments.paid_currency/exchange_rate/
    paid_amount/tendered_amount`, `sync_branding` accepte `settings.exchange_rate_htg`, email reçu avec devise payée.
  * `lib/features/payments/domain/currency.dart` (conversion, `money()`, `collectedByCurrency`), `PaymentCommand`/
    `GymPayment` étendus, `CashierMath` dans `collect_payment_dialog.dart` (choix USD/HTG, dû converti, monnaie).
    Wizard d'inscription utilise `CashierMath`. Réglage « Taux du jour » dans Paramètres › Salle (`branding_page.dart`).
  * Paiements (`payments_page.dart`) : filtres jour/semaine/mois/année/tout/plage, recherche, totaux par devise,
    groupés par jour, clic ⇒ `payment_detail_sheet.dart`. Rapports : lignes « réellement encaissé (USD/HTG) » + CSV.
  * Reçus : page `/receipts` (`receipts_page.dart`, menu pour tous les rôles, lecture seule), `ReceiptData.fromPayment`
    + `withLogo` (garde tous les champs), PDF avec devise payée/taux/caissier, WhatsApp = message formaté + lien PDF.
    3.3 : `ReceiptService.enqueueEmailWithRetry` (le paiement n'était pas encore synchronisé ⇒ RPC échouait en silence).
    Reste à vérifier côté serveur : migration 24 appliquée (bucket `receipts`), worker `send_emails` déployé.
  * 5.1 : wizard — email facultatif, NIF facultatif ; obligatoire = prénom, nom, téléphone/WhatsApp.
  * Tests : `test/currency_test.dart`.
  * Prochaine étape : 5.2 (mode rapide), puis Phase 6 (staff), Phase 7 (portail).

- 2026-10-19 (suite 2) — 5.2 Mode rapide terminé (analyze OK, 87 tests OK).
  * `lib/features/enrollment/presentation/enrollment_wizard_page.dart` :
    Toggle AppBar « Mode rapide (1 écran) » vs « Assistant par étapes » (mode rapide par défaut).
    1 seul écran avec : identité essentielle (prénom, nom, WhatsApp), sélection visuelle rapide du plan,
    date de début, caisse complète (modes de paiement, montant dû converti, devise USD/HTG, calcul automatique de la monnaie,
    option crédit, confirmation en caisse immédiate), volet accordéon pour options avancées (Photo, Sexe, NIF/CIN, Adresse, Urgence, PIN, Empreinte USB).
    Bouton d'action « Enregistrer & Encaisser » avec validation rapide et auto-skip empreinte pour enrôlement ultérieur.
  * `lib/l10n/strings_v5.dart` : nouvelles clés localisées (FR, HT, EN).
  * Prochaine étape : Phase 6 (Personnel vs Employés).

- 2026-10-20 — Phase 6 terminée (analyze 0 issues, 94 tests OK).
  * 6.1 : Permissions granulaires et POSTE (caissier, secrétaire, superviseur, personnalisé) dans `staff.permissions` (SQL 28),
    `manage_staff` Edge Function, `StaffRepository`, router redirects et menus restreints selon les droits.
  * 6.2 : Empreintes USB pour staff et propriétaire (`register_staff_fingerprint` RPC + fallback direct, `StaffRepository.saveFingerprints/clearFingerprints`),
    badge visuel d'empreinte dans la liste staff, actions enrôler / refaire / supprimer avec `FingerprintEnrollmentDialog.showGeneric`.
  * 6.3 : Déverrouillage d'application par empreinte sur le laptop (`unlock_page.dart`) : écoute continue de l'agent biométrique USB,
    bouton « Scanner l'empreinte », identification 1:N parmi les empreintes staff actives de la base locale,
    et restauration dynamique de session avec le profil et les permissions du staff identifié (`AppRuntime.unlockWithStaff`).
  * 6.4 : Rapport quotidien envoyé par email au propriétaire (`enqueue_daily_report` RPC dans SQL 28, template `daily_report` dans
    l'Edge Function `send_emails`, et bouton d'envoi immédiat par email sur la page `/reports`).
  * Prochaine étape : Phase 7 (Portail web membre securgym.com).

- 2026-10-20 (suite) — Frais d'inscription, Motifs de paiement & Phase 7.1 / 7.2 terminés (analyze 0 issues, tests OK).
  * SQL 29 (`supabase/sql/29_registration_fee_and_portal.sql`) :
    - Colonnes `payments.registration_fee`, `payments.plan_fee`, `payments.payment_reason`.
    - Colonne `plans.registration_fee`.
    - Table `portal_requests` (RLS + realtime) et RPCs `portal_submit` & `portal_get_gym`.
  * Tarifs & Formules (`plans_page.dart`, `plans_repository.dart`, `plan.dart`) :
    - Saisie et affichage des frais d'adhésion (`registration_fee`) pour chaque formule.
  * Inscription (`enrollment_wizard_page.dart`) :
    - Sélecteur de mode de frais d'inscription (en mode rapide et en mode étapes) :
      1. « Séparé (+ frais) » : Total = Prix du plan + Frais d'inscription.
      2. « Inclus dans le mois » : Les frais d'inscription incluent déjà le 1er mois.
      3. « Offert / 0 frais » : Frais d'inscription exonérés.
    - Montant des frais modifiable en direct, calcul automatique du total dû à la caisse.
    - Enregistrement des montants ventilés et du motif explicite (ex: « Inscription + 1er mois »).
  * Rapports financiers (`reports_page.dart`, `reports_repository.dart`, `report_pdf.dart`) :
    - Onglet Résumé : ventilation claire entre Totaux Inscriptions et Totaux Abonnements par devise.
    - Onglet Paiements : badge visuel affichant le Motif du paiement et le détail Frais vs Formule.
    - Export CSV : colonnes Motif, Frais inscription, Frais formule.
    - Export PDF : colonne « Motif » dans la table des paiements.
  * Phase 7.1 : Page d'adhésion web `/join/:code` (`portal_join_page.dart`) accessible publiquement, avec logo et nom du gym, liste des formules et tarifs, formulaire prospect, soumission sécurisée via `portal_submit`.
  * Phase 7.2 : Page de gestion `/portal-requests` (`portal_requests_page.dart`) dans la barre latérale pour la réception, filtres en attente / complétées, bouton WhatsApp direct, et action « Valider & Encaisser » pré-remplissant l'inscription (`/members/new`).
  * Prochaine étape : Phase 7.3 & 7.4 (Renouvellement membre via lien/QR et espace membre).

- 2026-10-21 — Demandes en ligne (Frais d'inscription & Reçu complet), Capture d'empreinte instantanée, Calcul 30 jours exact + Dates début/fin modifiables, Responsive design global :
  * `lib/features/portal/presentation/portal_process_dialog.dart` :
    - Ajout de la section complète « Frais d'inscription » pour les nouvelles inscriptions en ligne (bascule Ancien membre sans frais, modes `+ Frais`, `Inclus 1er mois`, `Offerts (0)` et saisie personnalisée du montant des frais).
    - Ajout des deux sélecteurs de dates : **Date de début** (recalcule automatiquement la date de fin) et **Date de fin** (modifiable manuellement par la secrétaire pour vérification ou ajustement).
    - Préchargement asynchrone des empreintes membres (`_preloadMembersWithFingerprints`) pour éliminer toute latence 1:N au moment du scan + bouton « Scanner » direct + synchronisation immédiate (`< 500ms`) vers le terminal IP `BioEntry W2`.
    - Envoi automatique du reçu officiel (`ReceiptService.autoEnqueue`) et impression avec ventilation complète (Frais d'inscription + Tarif formule + Période exacte).
  * `lib/features/payments/data/receipt_pdf.dart` & `lib/features/payments/presentation/receipt_sheet.dart` :
    - Ajout de `registrationFee`, `planFee` et `paymentReason` dans `ReceiptData` (`fromPayment`, `withLogo`) et affichage détaillé sur le reçu PDF, l'aperçu écran et le message WhatsApp.
  * `lib/features/subscriptions/domain/subscription_rules.dart`, `lib/features/enrollment/presentation/enrollment_wizard_page.dart`, `lib/features/members/presentation/member_detail_page.dart`, `lib/features/members/data/members_repository.dart` :
    - Correction de `subscriptionEnd(start, durationDays)` pour garantir 30 pleins jours (ex: 17 oct → 16 nov au lieu de 15 nov).
    - Ajout du double sélecteur **Date de début** + **Date de fin** dans l'assistant d'inscription (mode rapide & mode étapes) ainsi que dans la fenêtre de renouvellement d'abonnement (`_renew`).
  * `tools/access_agent/agent.dart` & `lib/core/biometrics/biometric_service.dart` :
    - Mutualisation (`Completer` partagé `_activeCapture`) des requêtes `/capture` concurrentes dans l'agent local afin qu'une ouverture de dialogue ou un clic manuel ne reçoive jamais `409 Conflict (busy)` et capte le doigt instantanément.
  * `lib/features/members/presentation/members_page.dart` & `lib/features/portal/presentation/portal_requests_page.dart` :
    - Refonte de `MembersPage` en `CustomScrollView` (`SliverList`) : lorsque le panneau de statistiques (`MembersStatsPanel`) est ouvert, toute la page défile de façon fluide sur toutes les tailles d'écran sans jamais masquer ni écraser la liste des membres.
    - Adaptation responsive des cartes de demandes en ligne (`LayoutBuilder` + `Wrap`).

- 2026-10-30 — Espace membre PWA par gym + 2e écran d'accès en vraie fenêtre (analyze OK, tests OK).
  * SQL `supabase/sql/34_member_portal.sql` (À APPLIQUER après 33, idempotent) : `member_accounts` (lien compte Auth ↔ membre PAR gym),
    `gym_announcements`, `portal_requests.auth_user_id`, RPC `member_portal_gyms/gym/check/link/attach_request/me/request_renewal`,
    policies Storage (logo public des gyms actifs, photo + reçus PDF du membre lui-même). Test : `supabase/tests/member_portal_test.ts`.
  * Routes publiques `/espace-membre` (liste des gyms + logos) et `/m/<gymId>` (connexion / activation / suivi d'inscription / tableau de bord
    4 onglets : accueil, activité, paiements, mon gym). Session membre ISOLÉE (`member_session.dart`, REST GoTrue direct : le client Supabase
    diffuse les connexions aux autres onglets via BroadcastChannel et déconnecterait le personnel).
  * Membres existants : email + téléphone de la fiche (ou n° de membre si la fiche n'a pas d'email) → mot de passe → lien. Inscription en ligne :
    case « Créer mon espace membre » dans `/join` → compte créé + demande rattachée → suivi en direct, activé automatiquement quand le gym valide.
  * PWA : manifest par gym (nom + logo redessiné en PNG carré) généré dans `web/index.html`, bannière « Installer » (Android prompt, iOS instructions).
  * Propriétaire : page `/member-space` (QR/lien, messages aux membres, comptes activés révocables).
  * 2e écran d'accès : `openAccessDisplayWindow` ouvre une vraie fenêtre (web `window.open ?display=1`, Windows 2e processus `--access-display`
    placé/maximisé sur le moniteur secondaire). Décisions transmises instantanément par `AccessDisplayBridge` (BroadcastChannel web / SSE local
    127.0.0.1:47812 Windows). Fenêtre 2e écran : pas de PIN, pas de déconnexion auto, pas de 2e moteur de sync, confinée à l'écran d'accès ;
    si la fenêtre principale est fermée elle surveille le terminal elle-même.
  * Reste à faire côté serveur : appliquer SQL 34 ; ajouter `https://securgym.com/m/*` aux Redirect URLs Supabase Auth (mot de passe oublié).
  * Correction (même jour) : la liste des gyms est sur la PAGE DE CONNEXION (`login_page.dart`) : laptop ≥ 960 px = 2 colonnes
    (`MemberGymsPanel` | carte de connexion), mobile = onglets « Propriétaire / Personnel » | « Espace membre ». `/espace-membre` ouvre
    la même page sur l'onglet membre. Bouton « Se connecter en tant que membre » → `/espace-membre/connexion` (`member_login_page.dart`,
    RPC `member_portal_my_gyms` ajoutée à SQL 34) : ouvre directement le gym du membre ou propose le choix.

- 2026-10-30 — Espace membre côté accueil : membres/accès, messagerie, modèles d'annonces ; profil modifiable par le membre (analyze OK, 100 tests OK, PGlite OK, 9 tests Deno OK).
  * SQL `34_member_portal.sql` (réappliquer — idempotent) : `member_messages` (conversation membre ↔ gym, realtime, accusés de lecture),
    `member_portal_send_message` (40/j), `member_portal_messages`, `member_portal_update_profile` (champs en liste blanche + photo
    contrôlée), `mp_is_portal_member`/`mp_can_write_photo`, policies Storage (le membre n'écrit que dans `member-photos/<gym>/<membre>/`).
    `member_portal_me` renvoie désormais le profil complet (whatsapp, birth_date, sex, adresse, urgence, responsable).
  * Edge Function `manage_member_account` (À DÉPLOYER : `supabase functions deploy manage_member_account`, mêmes variables que
    manage_staff) : le personnel crée/réinitialise le mot de passe d'un membre (compte Auth créé confirmé ou mot de passe réinitialisé,
    jamais sur un compte staff/partagé) et révoque l'accès (compte Auth orphelin supprimé).
  * `/member-space` réorganisée en 4 onglets : **Membres** (liste complète + statut du compte + accès/mot de passe + fiche),
    **Messages** (conversations membres, badge non lus, réponse, temps réel), **Annonces** (modèles prêts : horaires, fermeture,
    rappel paiement, promo, événement), **Lien/QR**.
  * Fiche membre (`/members/<id>`) : carte « Espace membre » avec statut du compte + création/réinitialisation du mot de passe.
  * Dashboard membre : 5 onglets (ajout **Messages** en temps réel) ; onglet Profil : « Modifier mon profil » (photo téléversée,
    naissance, sexe, téléphones, urgence…) et « Mot de passe » (GoTrue direct).

- 2026-10-30 — Déploiement Supabase + correctif « Connexion Internet indisponible » sur l'accès membre.
  * Déployé via Management API/CLI : `34_member_portal.sql` appliqué en intégralité (`member_messages`, RPCs messages/profil/`my_gyms`),
    Edge Function `manage_member_account` ACTIVE (verify_jwt, 401 sans token), Redirect URLs Auth (`securgym.com/m/*`, `www.securgym.com`,
    localhost), `member_messages` dans la publication Realtime. Toutes les tables/colonnes/fonctions 01→34 vérifiées présentes.
  * Cause réelle du faux « Connexion Internet indisponible » : `client.functions.invoke` lève `FunctionException` pour toute réponse
    non-2xx (origin_denied, shared_account, weak_password…) et le client la masquait en « network ». `member_account_admin._invoke`
    lit désormais `FunctionException.details.error` et remonte le vrai code (+ libellé `origin_denied`).
  * `authorizedHandler` autorise désormais les origines `localhost`/`127.0.0.1` (tous ports) pour le dev, en plus de
    `GYMDESK_ALLOWED_ORIGINS`. ⚠️ Pour la production : définir le secret `GYMDESK_ALLOWED_ORIGINS=https://securgym.com,https://www.securgym.com`
    dans Edge Functions → Secrets (sans lui, tout appel navigateur → `origin_denied`). Redéployer la fonction après ce commit.

- 2026-10-30 — Correctif « Ces données sont refusées » sur la page Paramètres/branding (JL FITNESS).
  * Trois causes trouvées en prod : `gyms.settings.biometric_config` (écrit par biometric_settings_page via update direct)
    absent de la whitelist `sync_branding` → toute sauvegarde rejetée ; `phone` 35 > limite 32 ; `logo_url` exigeait le
    préfixe `gym-assets/<uuid>/` alors que le client stocke `<gym_id>/logos/<uuid>.png`.
  * `supabase/sql/35_branding_fix.sql` (appliqué via Management API + vérifié) : whitelist + `biometric_config`
    (objet ≤ 16 Ko), phone 32→64 (client `_validate` + branding_page alignés), logo accepte `<gym_id>/logos/...`
    restreint au dossier de la salle. Assertion ajoutée à `member_portal_tests.sql` + chaîne PGlite étendue (test OK).

- 2026-10-30 — Admin plateforme : plans en français, détail gym cliquable, fond + logo SecurGYM, signup corrigé.
  * Offres : `platform_offers` normalisées en français en prod (PLAN 1 : DÉMARRAGE / 2 : CROISSANCE / 3 : PROFESSIONNEL /
    4 : ENTREPRISE) — les UPDATE doivent être envoyés une requête à la fois via l'API Management (les multi-statements
    réencodent l'UTF-8). `19_one_time_payment_offers.sql` et `PlatformOffer.defaultAnnualPlans` alignés sur la config live
    (basic 150 m./install incluse, medium 1 000 m./install sur commande, pro 1 000 m. + 1 tablette + 200 badges, enterprise
    illimité + 1 tablette + 500 badges). `loadOffers` n'utilise le fallback que si les plans officiels sont absents.
  * `supabase/sql/36_admin_gym_detail.sql` (appliqué + vérifié en prod) : `platform_gym_detail` (fiche complète : stats
    membres/abonnements actifs, contrat/offre, totaux paiements, propriétaire/contact) et `platform_update_gym`
    (édition super-admin avec contrôle de version). RLS : `is_super_admin()` uniquement.
  * UI admin : lignes de `/gyms` cliquables → `/gyms/<id>` (page détail ~800 lignes : stats, contrat, propriétaire,
    actions modifier/suspendre/réactiver/réinitialiser le mot de passe propriétaire) ; shell admin avec `SecurGymBackground`
    + logo SecurGYM ; `offers_page` tout en français et lignes capacités basées sur la config réelle (tablette incluse vs
    sur commande, badges, installation).
  * Signup : cartes de plan directement sélectionnables (plus de slider), `_offerId` par défaut `plan_basic`,
    `create_gym_with_owner` durci (validation des champs + offer_id, erreurs d'insert vérifiées, nettoyage des enregistrements
    partiels, réutilisation sûre d'un utilisateur Auth existant) et redéployée.
  * Réparé `send_emails/templates.ts` (branche daily_report corrompue dans HEAD) — `deno check` OK.
  * Tests : `admin_offers_test.ts` mis à jour (les offres `per_member`/`tiered` n'existent plus → `plan_basic`) ;
    `platform_offers_test.dart` réécrit sur la config actuelle ; `admin_gym_detail_test.ts` (PGlite) OK.
    Résultat : analyze propre, 40/40 Deno, suite Flutter verte.

# Conformité Légale & Gestion du Consentement — GymDesk V3

Guide d'application des principes RGPD (Règlement Général sur la Protection des Données) et des législations locales sur la protection de la vie privée.

---

## 1. Cadre Juridique Applicable
Les données biométriques constituent des **données sensibles** à caractère particulier. Le traitement de ces données est strictement encadré par :
1. Le **consentement libre, explicite et éclairé** de l'intéressé.
2. Le principe de **proportionnalité** et de **finalité déterminée** (contrôle d'accès physique au club).
3. Le **droit à l'alternative sans pénalité** (possibilité pour un membre de refuser la biométrie et d'utiliser un code PIN ou une vérification par le personnel d'accueil).

## 2. Procédure d'Enrôlement et Recueil du Consentement
- Lors de l'enrôlement (Étape 4 du Magicien d'Inscription), la boîte de dialogue `BiometricConsentDialog` affiche le texte légal complet dans la langue choisie par le membre (Créole haïtien, Français ou Anglais).
- La case à cocher engage à la fois le membre et l'agent d'accueil témoin.
- L'horodatage, l'identifiant du membre et l'identifiant de l'agent témoin sont consignés dans la table PostgreSQL `biometric_consents`.

## 3. Droit à la Révocation et à l'Oubli (Suppression Immédiate)
- À tout moment, un membre peut demander l'effacement de ses données biométriques sans justification.
- L'action dans le logiciel :
  1. Supprime définitivement les gabarits de la table `member_fingerprints`.
  2. Réinitialise le flag `fingerprint_registered = false` sur la fiche membre.
  3. Purge immédiatement le cache mémoire et local SQLite.
  4. Enregistre la révocation dans le journal d'audit `audit_logs` avec la mention `biometrics_revoked`.

## 4. Registre des Traitements
Chaque club de sport utilisant GymDesk doit tenir à disposition son registre simplifié :
- **Finalité** : Gestion des accès et sécurité des locaux du club.
- **Catégories de données** : Minuties vectorielles chiffrées d'empreinte (doigt principal et doigt de secours).
- **Destinataires** : Système informatique exclusif du club. Aucun transfert vers des tiers.
- **Durée de conservation** : Durée de l'adhésion active + 30 jours après résiliation définitive, ou suppression immédiate sur demande.

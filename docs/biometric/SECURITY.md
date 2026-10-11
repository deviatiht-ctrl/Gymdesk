# Architecture de Sécurité Biométrique — GymDesk V3

Ce document détaille les principes cryptographiques, l'isolation des données et la protection des gabarits d'empreintes digitales dans le système GymDesk.

---

## 1. Principe Zéro-Image (No Raw Biometrics)
- **Aucune image d'empreinte digitale brute (BMP, PNG, WSQ)** n'est jamais stockée sur le disque, ni transmise sur le réseau, ni enregistrée dans la base de données.
- Dès la capture par le capteur Suprema BioMini ou les lecteurs partenaires, l'image est transformée en mémoire vive (RAM) en un **vecteur de minuties** (format Suprema 384 octets ou ISO 19794-2).
- Le buffer image est immédiatement écrasé en mémoire vive après extraction.

## 2. Irréversibilité Mathématique des Gabarits
- Les gabarits d'empreintes (templates) sont mathématiquement non rétro-ingéniables. Il est impossible de reconstruire l'empreinte d'origine d'un individu à partir d'un fichier de minuties.
- Chaque gabarit représente uniquement les coordonnées relatives des bifurcations et des terminaisons de crêtes papillaires.

## 3. Chiffrement au Repos (At Rest)
- Dans la table Supabase `member_fingerprints` ainsi que dans le cache local SQLite / Drift, les gabarits sont chiffrés avec **AES-256-GCM**.
- Chaque enregistrement possède un vecteur d'initialisation unique (IV) de 12 octets et un tag d'authentification de 16 octets.
- La clé de chiffrement dérive de l'identifiant du club de sport (`gym_id`) et du secret machine local, empêchant tout déchiffrement croisé entre deux salles de sport distinctes.

## 4. Chiffrement en Transit (In Transit)
- Toutes les communications entre le client desktop / web et le serveur Supabase sont chiffrées en **TLS 1.3 / HTTPS**.
- Les échanges locaux avec l'agent d'accès (`http://127.0.0.1:47811`) sont strictement confinés à l'interface de bouclage local (`loopback / localhost`), inaccessibles depuis le réseau externe.

## 5. Politiques RLS (Row Level Security)
- La table `member_fingerprints` est protégée par RLS au niveau de la base PostgreSQL :
  ```sql
  CREATE POLICY "gym_staff_access_fingerprints" ON member_fingerprints
    FOR ALL USING (gym_id = (auth.jwt() -> 'app_metadata' ->> 'gym_id')::uuid);
  ```
- Un compte staff d'une salle ne peut en aucun cas lire ou interroger les gabarits d'une autre salle.

## 6. Logs Techniques Anonymisés
- Les journaux d'audit et les rapports de diagnostic exportés ne contiennent **aucun gabarit d'empreinte**.
- Seuls les identifiants techniques hachés (SHA-256 tronqué), les scores de qualité NFIQ (0-100) et les horodatages sont conservés.

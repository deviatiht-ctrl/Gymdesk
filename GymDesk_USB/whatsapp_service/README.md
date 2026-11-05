# SecurGYM / GymDesk - Sèvis WhatsApp (whatsapp-web.js)

Mikwo-sèvis Node.js sa a entegre bibliyotèk `whatsapp-web.js` la dirèkteman nan SecurGYM / GymDesk pou voye resi peman, notifikasyon, ak rapèl fen abònman sou WhatsApp otomatikman.

---

## 🚀 Kijan pou w Kòmanse (Fasil anpil)

### 1. Demare Sèvis la
Fè yon doub klik sou fichye:
👉 **`LANCER_WHATSAPP.bat`**
*(Oswa pou l kouri an silans an aryè plan: **`Demarrer_WhatsApp_Silencieux.vbs`**)*

Si Node.js pa t enstale sou machin nan, script la ap enstale l otomatikman ak tout depandans yo.

### 2. Konekte WhatsApp sou Panèl Admin nan
1. Louvri GymDesk / SecurGYM.
2. Ale nan meni **Admin** > **WhatsApp** (oswa **Paramèt** > **WhatsApp**).
3. Pran telefòn ou, ouvri aplikasyon **WhatsApp**.
4. Ale nan **Paramèt** > **Aparèy konekte (Linked devices)**.
5. Peze **Konekte yon aparèy** epi vize kamera telefòn ou sou kòd QR ki parèt sou ekran an.
6. Le pli vit ke w eskane l, sistèm nan ap make:
   🟢 **WhatsApp Konekte avèk Siksè** ak nimewo telefòn ou !

---

## ⚙️ Enskripsyon Nimewo Valid & Tès
Nan paj Admin WhatsApp la:
- **Nimewo WhatsApp Valid (Admin / Tès)** : Antre nimewo telefòn valid ou a (egz: `50937001122`).
- **Kòd Peyi pa defo** : `509` (Ayiti) oswa kòd peyi pa w la.
- **Bwat Tès** : Klike sou "Voye Mesaj Tès Kounye a" pou verifye ke tout bagay ap mache dirèkteman sou telefòn ou !

---

## 📡 API Endpoints (Pò 47812)
- `GET /health` : Tcheke si sèvis la sou pye.
- `GET /api/status` : Retounen estati koneksyon (`READY`, `SCAN_QR`, `INITIALIZING`, etc.), kòd QR an base64, ak nimewo ki konekte a.
- `GET /api/qr.png` : Retounen kòd QR la sou fòm imaj PNG dirèk.
- `POST /api/send` : Voye yon mesaj bay yon nimewo (`{ "to": "50936001122", "message": "..." }`).
- `POST /api/test` : Voye yon mesaj tès bay nimewo valid la.
- `POST /api/config` : Mete ajou konfigirasyon an (`validNumber`, `defaultCountryCode`, etc.).
- `POST /api/initialize` : Rafrechi kòd QR la oswa rekonekte.
- `POST /api/logout` : Dekonekte sesyon an pou chanje telefòn.

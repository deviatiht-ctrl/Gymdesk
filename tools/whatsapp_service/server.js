const express = require('express');
const cors = require('cors');
const qrcode = require('qrcode');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');

// Pwoteje pwosesis la kont erè CDP / Rezo ki ka soti nan Puppeteer
process.on('unhandledRejection', (reason) => {
  console.warn('[Cluster] Intercepted unhandledRejection:', reason && reason.message ? reason.message : reason);
});
process.on('uncaughtException', (err) => {
  console.warn('[Cluster] Intercepted uncaughtException:', err && err.message ? err.message : err);
});

const PORT = process.env.PORT || 47812;
const CONFIG_FILE = path.join(__dirname, 'config.json');
const AUTH_DIR = path.join(__dirname, '.wwebjs_auth');

// Supabase Cloud Bridge Config (pou Tablet, Telefòn, ak Web)
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://jrhdegdvdqnxstpdzbya.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpyaGRlZ2R2ZHFueHN0cGR6YnlhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEyOTM2NDksImV4cCI6MjEwNjg2OTY0OX0.O8WMsF2z447mdWj6gNMyaJ9Q8eTFQwKZyLMMsxrfx5Y';

// Paramèt Delè Sekirite Anti-Spam & Anti-Bann (Human Pacing)
const PACING_CONFIG = {
  minDelayMs: 25000,           // Omwen 25 segonn ant chak mesaj sou MENM nimewo a
  maxJitterMs: 25000,          // + 0 a 25 segonn varyab (total 25s - 50s)
  typingDelayMinMs: 3000,      // Similasyon moun k ap tape: 3 a 5 segonn
  typingDelayMaxMs: 5500,
  batchPauseAfterCount: 7,     // Apre chak 7 mesaj sou menm nimewo a, pran yon poz
  batchPauseDurationMs: 180000,// Poz 3 minit (180s) pou repoze nimewo a
  defaultDailyLimit: 40,       // Maksimòm 40 mesaj san danje pa nimewo chak jou
};

// 1. Chaje konfigirasyon lokal
let config = {
  validNumber: '50932986751',
  backupNumber: '',
  defaultCountryCode: '509',
  autoSendWelcome: true,
  autoSendReceipts: true,
  autoSendReminders: true,
  reminderDaysBefore: 7,
  port: PORT
};

function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_FILE)) {
      const data = fs.readFileSync(CONFIG_FILE, 'utf8');
      config = { ...config, ...JSON.parse(data) };
    }
  } catch (_) {}
}
function saveConfig() {
  try {
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2), 'utf8');
  } catch (_) {}
}
loadConfig();

// 2. Jwenn chemen Chrome oswa Edge sou Windows pou Puppeteer
function getBrowserExecutablePath() {
  if (process.env.PUPPETEER_EXECUTABLE_PATH) {
    return process.env.PUPPETEER_EXECUTABLE_PATH;
  }
  const possiblePaths = [
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    path.join(process.env.LOCALAPPDATA || '', 'Microsoft\\Edge\\Application\\msedge.exe'),
    path.join(process.env.LOCALAPPDATA || '', 'Google\\Chrome\\Application\\chrome.exe'),
  ];
  for (const p of possiblePaths) {
    if (fs.existsSync(p)) return p;
  }
  return undefined;
}

// 3. Netwaye fichye lock Chromium sèlman nan rasin sesyon an (pa manyen LevelDB!)
function cleanSessionLockFiles(sessionDirPath) {
  try {
    if (!fs.existsSync(sessionDirPath)) return;
    const candidates = [sessionDirPath, path.join(sessionDirPath, 'Default')];
    for (const d of candidates) {
      if (!fs.existsSync(d)) continue;
      const files = fs.readdirSync(d, { withFileTypes: true });
      for (const f of files) {
        if (f.isFile()) {
          const nameLower = f.name.toLowerCase();
          if (
            nameLower === 'singletonlock' ||
            nameLower === 'singletoncookie' ||
            nameLower === 'singletonsocket' ||
            nameLower === 'devtoolsactiveport' ||
            nameLower === 'lockfile'
          ) {
            try {
              fs.unlinkSync(path.join(d, f.name));
            } catch (_) {}
          }
        }
      }
    }
  } catch (_) {}
}

// 4. Netwaye epi mete nimewo a nan bon fòma entènasyonal (egz: 50937001122)
function cleanPhoneNumber(phone) {
  if (!phone) return null;
  let digits = String(phone).replace(/\D/g, '');
  if (!digits) return null;
  const defaultCode = (config.defaultCountryCode || '509').replace(/\D/g, '');
  if (digits.length === 8 && defaultCode) {
    digits = defaultCode + digits;
  }
  return digits;
}

// ============================================================================
// KLAZ INSTANS KONT WHATSAPP (WhatsAppAccountInstance)
// ============================================================================
class WhatsAppAccountInstance {
  constructor(accountIndex, label = `Liy ${accountIndex}`, dailyLimit = 40) {
    this.accountIndex = accountIndex;
    this.label = label;
    this.dailyLimit = dailyLimit || 40;
    this.client = null;
    this.status = 'DISCONNECTED'; // DISCONNECTED, INITIALIZING, SCAN_QR, AUTHENTICATED, READY, RESTRICTED, ERROR
    this.rawQrCode = null;
    this.qrCodeDataUrl = null;
    this.phone = null;
    this.pushName = null;
    this.lastError = null;
    this.isInitializing = false;
    this.isBusy = false;
    this.lastSentAt = 0;
    this.sentToday = 0;
    this.consecutiveSentCount = 0;
    this.restrictedUntil = null;
    this.restrictionReason = null;
    this.sessionDir = path.join(AUTH_DIR, `session-account_${accountIndex}`);
  }

  get isReady() {
    return this.status === 'READY' && this.client !== null && !this.isRestricted;
  }

  get isRestricted() {
    if (this.status === 'RESTRICTED') {
      if (this.restrictedUntil && new Date(this.restrictedUntil).getTime() > Date.now()) {
        return true;
      }
      // Restriksyon fin pase
      this.status = 'DISCONNECTED';
      this.restrictedUntil = null;
      this.restrictionReason = null;
    }
    return false;
  }

  // Tcheke si kont sa a ka pran yon nouvo mesaj kounye a (Human Pacing)
  canSendNow() {
    if (!this.isReady) return false;
    if (this.isBusy) return false;
    if (this.sentToday >= this.dailyLimit) return false;

    const now = Date.now();
    // 1. Tcheke si l nan poz repo apre 7 mesaj
    if (this.consecutiveSentCount >= PACING_CONFIG.batchPauseAfterCount) {
      if (now - this.lastSentAt < PACING_CONFIG.batchPauseDurationMs) {
        return false; // Ap repoze pou evite bot ban
      } else {
        this.consecutiveSentCount = 0; // Fin repoze, rekòmanse
      }
    }

    // 2. Tcheke delè minimòm ant chak mesaj (25s - 50s)
    const requiredDelay = PACING_CONFIG.minDelayMs + Math.floor(Math.random() * PACING_CONFIG.maxJitterMs);
    if (now - this.lastSentAt < requiredDelay) {
      return false;
    }

    return true;
  }

  async sendHeartbeat() {
    try {
      await fetch(`${SUPABASE_URL}/rest/v1/rpc/platform_whatsapp_account_heartbeat`, {
        method: 'POST',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          p_account_index: this.accountIndex,
          p_service_status: this.status,
          p_phone_number: this.phone,
          p_push_name: this.pushName,
          p_qr_code: this.status === 'SCAN_QR' ? (this.qrCodeDataUrl || this.rawQrCode) : null,
          p_last_error: this.lastError,
        }),
      });
    } catch (_) {}
  }

  async markRestricted(hours = 24, reason = 'Restriksyon sekirite WhatsApp') {
    this.status = 'RESTRICTED';
    this.restrictedUntil = new Date(Date.now() + hours * 3600 * 1000).toISOString();
    this.restrictionReason = reason;
    this.qrCodeDataUrl = null;
    this.rawQrCode = null;
    console.warn(`[Liy ${this.accountIndex}] 🔴 Restreint pou ${hours}h: ${reason}`);
    try {
      await fetch(`${SUPABASE_URL}/rest/v1/rpc/platform_whatsapp_account_report_restricted`, {
        method: 'POST',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          p_account_index: this.accountIndex,
          p_hours: hours,
          p_reason: reason,
        }),
      });
    } catch (_) {}
    await this.destroy();
  }

  async init() {
    if (this.isRestricted) {
      console.log(`[Liy ${this.accountIndex}] Nan poz restriksyon jouk: ${this.restrictedUntil}`);
      return;
    }
    if (this.isInitializing) return;
    this.isInitializing = true;
    this.status = 'INITIALIZING';
    this.lastError = null;
    this.sendHeartbeat();

    console.log(`[Liy ${this.accountIndex} - ${this.label}] Demaraj sesyon WhatsApp...`);

    try {
      cleanSessionLockFiles(this.sessionDir);
      const execPath = getBrowserExecutablePath();

      this.client = new Client({
        authStrategy: new LocalAuth({
          clientId: `account_${this.accountIndex}`,
          dataPath: AUTH_DIR,
        }),
        webVersionCache: { type: 'none' },
        puppeteer: {
          headless: 'new',
          args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-accelerated-2d-canvas',
            '--no-first-run',
            '--no-zygote',
            '--disable-gpu',
            '--disable-extensions',
            '--disable-background-timer-throttling',
            '--disable-backgrounding-occluded-windows',
            '--disable-renderer-backgrounding',
            '--disable-features=Translate,OptimizationHints,MediaRouter',
          ],
          executablePath: execPath,
        },
      });

      this.client.on('qr', async (qr) => {
        console.log(`[Liy ${this.accountIndex}] 📷 Nouvo Kòd QR resevwa. Pare pou eskanè!`);
        this.status = 'SCAN_QR';
        this.rawQrCode = qr;
        this.isInitializing = false;
        try {
          this.qrCodeDataUrl = await qrcode.toDataURL(qr, { margin: 2, scale: 8 });
        } catch (_) {}
        this.sendHeartbeat();
      });

      this.client.on('authenticated', () => {
        console.log(`[Liy ${this.accountIndex}] Otantifikasyon reyisi!`);
        this.status = 'AUTHENTICATED';
        this.rawQrCode = null;
        this.qrCodeDataUrl = null;
        this.sendHeartbeat();
      });

      this.client.on('ready', async () => {
        console.log(`[Liy ${this.accountIndex}] ✅ Kliyan WhatsApp pare nèt pou voye mesaj!`);
        this.status = 'READY';
        this.isInitializing = false;
        this.lastError = null;
        try {
          if (this.client && this.client.info) {
            this.phone = this.client.info.wid ? this.client.info.wid.user : null;
            this.pushName = this.client.info.pushname || null;
            console.log(`[Liy ${this.accountIndex}] Konekte kòm: ${this.pushName || 'Enkoni'} (${this.phone})`);
          }
        } catch (_) {}
        this.sendHeartbeat();
      });

      this.client.on('disconnected', (reason) => {
        console.warn(`[Liy ${this.accountIndex}] Kliyan dekonekte:`, reason);
        const reasonStr = String(reason || '').toUpperCase();
        if (reasonStr.includes('LOGOUT') || reasonStr.includes('RESTRICT') || reasonStr.includes('BAN')) {
          this.markRestricted(24, `Dekoneksyon fòse pa WhatsApp (${reason})`);
        } else {
          this.status = 'DISCONNECTED';
          this.phone = null;
          this.pushName = null;
          this.isInitializing = false;
          this.sendHeartbeat();
        }
      });

      this.client.on('auth_failure', (msg) => {
        console.error(`[Liy ${this.accountIndex}] Echèk otantifikasyon:`, msg);
        this.status = 'ERROR';
        this.lastError = msg;
        this.isInitializing = false;
        this.sendHeartbeat();
      });

      await this.client.initialize();
    } catch (err) {
      console.error(`[Liy ${this.accountIndex}] Erè inisyalizasyon:`, err.message);
      this.status = 'ERROR';
      this.lastError = err.message;
      this.isInitializing = false;
      this.sendHeartbeat();
    }
  }

  async destroy() {
    try {
      if (this.client) {
        if (this.client.pupBrowser) {
          const pid = this.client.pupBrowser.process() ? this.client.pupBrowser.process().pid : null;
          if (pid) {
            try { execSync(`taskkill /F /T /PID ${pid}`, { stdio: 'ignore' }); } catch (_) {}
          }
        }
        await this.client.destroy().catch(() => {});
      }
    } catch (_) {}
    this.client = null;
    this.isInitializing = false;
    this.isBusy = false;
    cleanSessionLockFiles(this.sessionDir);
  }

  // Voye mesaj ak similasyon moun k ap tape (Human Presence Simulation)
  async sendWithHumanPresence(chatId, content, options = {}, outboxId = null) {
    if (!this.isReady) {
      throw new Error(`Liy ${this.accountIndex} pa pare oswa li restreint.`);
    }

    this.isBusy = true;
    try {
      // 1. Voye siyal prezans "Online"
      try { await this.client.sendPresenceAvailable(); } catch (_) {}

      // 2. Simile yon moun k ap tape tèks la
      try { await this.client.sendPresenceTyping(chatId); } catch (_) {}
      const typingMs = PACING_CONFIG.typingDelayMinMs + Math.floor(Math.random() * (PACING_CONFIG.typingDelayMaxMs - PACING_CONFIG.typingDelayMinMs));
      await new Promise((r) => setTimeout(r, typingMs));

      // 3. Voye mesaj la
      let res;
      try {
        res = await this.client.sendMessage(chatId, content, options);
      } catch (sendErr) {
        const errMsg = String(sendErr && sendErr.message ? sendErr.message : sendErr);
        // Si WhatsApp detekte restriksyon oswa frame detached
        if (errMsg.includes('401') || errMsg.includes('403') || errMsg.includes('rate-overlimit') || errMsg.includes('restricted')) {
          await this.markRestricted(24, errMsg);
          throw new Error(`Nimewo a fètke resevwa restriksyon pa WhatsApp: ${errMsg}`);
        }
        throw sendErr;
      }

      // 4. Remete siyal prezans nòmal
      try { await this.client.sendPresenceAvailable(); } catch (_) {}

      // 5. Mete ajou statistik lokal ak Supabase
      this.lastSentAt = Date.now();
      this.sentToday += 1;
      this.consecutiveSentCount += 1;

      try {
        await fetch(`${SUPABASE_URL}/rest/v1/rpc/platform_whatsapp_account_record_send`, {
          method: 'POST',
          headers: {
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            p_account_index: this.accountIndex,
            p_message_id: outboxId,
          }),
        });
      } catch (_) {}

      console.log(`[Liy ${this.accountIndex} - ${this.phone || this.label}] ✅ Mesaj voye bay ${chatId} (${this.sentToday}/${this.dailyLimit} jodi a).`);
      return res;
    } finally {
      this.isBusy = false;
    }
  }
}

// ============================================================================
// CLUSTER MANAGER (Kowòdone tout kont yo ak Distribisyon Mesaj)
// ============================================================================
class AccountCluster {
  constructor() {
    this.accounts = new Map(); // accountIndex -> WhatsAppAccountInstance
    this.isDispatching = false;
    this.isSyncing = false;
  }

  getAccount(index) {
    return this.accounts.get(Number(index));
  }

  getAllAccounts() {
    return Array.from(this.accounts.values()).sort((a, b) => a.accountIndex - b.accountIndex);
  }

  // Rale lis kont yo depi Supabase epi inisyalize sa ki manke yo
  async syncAccountsFromSupabase() {
    if (this.isSyncing) return;
    this.isSyncing = true;
    try {
      const url = `${SUPABASE_URL}/rest/v1/rpc/platform_whatsapp_accounts_list`;
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({}),
      });

      if (res.ok) {
        const rows = await res.json();
        if (Array.isArray(rows)) {
          for (const row of rows) {
            const idx = row.account_index;
            let instance = this.accounts.get(idx);

            if (!instance) {
              instance = new WhatsAppAccountInstance(idx, row.label, row.daily_limit);
              this.accounts.set(idx, instance);
            }

            instance.label = row.label;
            instance.dailyLimit = row.daily_limit || 40;
            instance.sentToday = row.sent_today || 0;

            // Si kont lan make RESTREINT nan baz done a
            if (row.service_status === 'RESTRICTED' && row.restricted_until) {
              instance.status = 'RESTRICTED';
              instance.restrictedUntil = row.restricted_until;
              instance.restrictionReason = row.restriction_reason;
            }

            // Si kont lan make aktif men li poko lanse epi li pa restreint
            if (row.is_enabled && !instance.isRestricted && instance.status === 'DISCONNECTED' && !instance.isInitializing) {
              // Lanse kont lan ak yon ti entèval ant chak pou pa chaje CPU a
              setTimeout(() => instance.init(), idx * 4000);
            }
          }
        }
      }
    } catch (e) {
      console.warn('[Cluster] Erè senkronizasyon kont:', e.message);
    } finally {
      this.isSyncing = false;
    }
  }

  // Jwenn pwochen kont ki kalifye e ki pare pou voye (Round-Robin & Least Recently Used)
  getNextAvailableAccount() {
    const readyAccounts = this.getAllAccounts().filter((acc) => acc.canSendNow());
    if (readyAccounts.length === 0) return null;

    // Chwazi kont ki gen pi lontan depi l voye yon mesaj (Least Recently Used)
    readyAccounts.sort((a, b) => a.lastSentAt - b.lastSentAt);
    return readyAccounts[0];
  }

  // Distribiye mesaj k ap tann nan outbox la sou kont ki disponib yo
  async dispatchPendingOutboxMessages() {
    if (this.isDispatching) return;
    this.isDispatching = true;

    try {
      const assignedAccount = this.getNextAvailableAccount();
      if (!assignedAccount) {
        // Okenn liy pa lib kounye a (swa y ap respekte delè moun 30s la, swa nan poz repo, oswa okenn liy poko konekte)
        return;
      }

      // Rale 1 mesaj ki nan pending
      const url = `${SUPABASE_URL}/rest/v1/whatsapp_messages_outbox?status=eq.pending&order=created_at.asc&limit=1`;
      const res = await fetch(url, {
        method: 'GET',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
        },
      });

      if (!res.ok) return;
      const messages = await res.json();
      if (!Array.isArray(messages) || messages.length === 0) return;

      const item = messages[0];

      // Mete l kòm processing touswit
      await fetch(`${SUPABASE_URL}/rest/v1/whatsapp_messages_outbox?id=eq.${item.id}`, {
        method: 'PATCH',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          status: 'processing',
          assigned_account_index: assignedAccount.accountIndex,
          processed_at: new Date().toISOString(),
        }),
      });

      const cleanPhone = cleanPhoneNumber(item.to_phone);
      if (!cleanPhone || cleanPhone.length < 8) {
        await fetch(`${SUPABASE_URL}/rest/v1/whatsapp_messages_outbox?id=eq.${item.id}`, {
          method: 'PATCH',
          headers: {
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ status: 'failed', error_message: 'Nimewo telefòn destinataire pa valid' }),
        });
        return;
      }

      const chatId = `${cleanPhone}@c.us`;

      try {
        let sendResult;
        if (item.pdf_base64 && typeof item.pdf_base64 === 'string') {
          try {
            const media = new MessageMedia('application/pdf', item.pdf_base64, item.pdf_file_name || 'Recu.pdf');
            sendResult = await assignedAccount.sendWithHumanPresence(chatId, media, { caption: item.message.trim() }, item.id);
          } catch (_) {
            sendResult = await assignedAccount.sendWithHumanPresence(chatId, item.message.trim(), {}, item.id);
          }
        } else {
          sendResult = await assignedAccount.sendWithHumanPresence(chatId, item.message.trim(), {}, item.id);
        }

        // Siksè voye
        await fetch(`${SUPABASE_URL}/rest/v1/whatsapp_messages_outbox?id=eq.${item.id}`, {
          method: 'PATCH',
          headers: {
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            status: 'sent',
            sent_by_phone: assignedAccount.phone,
            sent_at: new Date().toISOString(),
          }),
        });
      } catch (sendErr) {
        console.warn(`[Cluster] Echèk voye mesaj sou Liy ${assignedAccount.accountIndex}:`, sendErr.message);
        // Remete mesaj la kòm pending pou yon lòt liy nan cluster a ka pran l!
        await fetch(`${SUPABASE_URL}/rest/v1/whatsapp_messages_outbox?id=eq.${item.id}`, {
          method: 'PATCH',
          headers: {
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            status: 'pending',
            error_message: `Echwe sou Liy ${assignedAccount.accountIndex} (${sendErr.message}); ap re-eseye sou yon lòt liy.`,
            processed_at: null,
          }),
        });
      }
    } catch (_) {
    } finally {
      this.isDispatching = false;
    }
  }

  // Voye yon mesaj manyèl / tès sou cluster a
  async sendMessageAnywhere(to, message, mediaBase64 = null, mediaName = null) {
    const cleanPhone = cleanPhoneNumber(to);
    if (!cleanPhone || cleanPhone.length < 8) {
      throw new Error('Nimewo destinataire a pa valid.');
    }
    const chatId = `${cleanPhone}@c.us`;

    // Jwenn nenpòt kont ki pare kounye a
    const available = this.getAllAccounts().filter((a) => a.isReady && !a.isBusy);
    if (available.length === 0) {
      throw new Error('Okenn liy WhatsApp pa pare oswa konekte pou voye mesaj kounye a.');
    }
    available.sort((a, b) => a.lastSentAt - b.lastSentAt);
    const chosen = available[0];

    if (mediaBase64) {
      const media = new MessageMedia('application/pdf', mediaBase64, mediaName || 'Document.pdf');
      return await chosen.sendWithHumanPresence(chatId, media, { caption: message.trim() });
    } else {
      return await chosen.sendWithHumanPresence(chatId, message.trim());
    }
  }

  // Verifikasyon rapèl échéance pou tout gym
  async runCronExpirationReminders(targetGymId = null) {
    try {
      const url = `${SUPABASE_URL}/rest/v1/rpc/cron_check_whatsapp_expiration_reminders`;
      const body = targetGymId ? JSON.stringify({ p_target_gym_id: targetGymId }) : JSON.stringify({});
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
          'Content-Type': 'application/json',
        },
        body,
      });
      if (res.ok) {
        const result = await res.json();
        console.log(`[Cron Expiration] ✅ Verifikasyon fèt: ${result.queued_count} nouvo rapèl mete nan outbox.`);
        return result;
      }
    } catch (err) {
      console.warn('[Cron Expiration] Erè rezo:', err.message);
    }
    return null;
  }
}

const cluster = new AccountCluster();

// ============================================================================
// EXPRESS API ROUTES
// ============================================================================
const app = express();
app.use(cors());
app.use(express.json({ limit: '25mb' }));
app.use(express.urlencoded({ extended: true, limit: '25mb' }));

app.get('/health', (req, res) => {
  res.json({ ok: true, service: 'securgym-whatsapp-cluster', accounts: cluster.accounts.size });
});

// 1. Estati jeneral cluster la ak premye kont la (Backwards compatibility)
app.get('/api/status', (req, res) => {
  const accounts = cluster.getAllAccounts();
  const readyCount = accounts.filter((a) => a.isReady).length;
  const primary = accounts[0] || null;

  res.json({
    ok: true,
    status: primary ? primary.status : 'DISCONNECTED',
    phone: primary ? primary.phone : null,
    pushname: primary ? primary.pushName : null,
    qr: primary ? primary.qrCodeDataUrl : null,
    rawQr: primary ? primary.rawQrCode : null,
    cluster: {
      totalAccounts: accounts.length,
      readyAccounts: readyCount,
      accounts: accounts.map((a) => ({
        index: a.accountIndex,
        label: a.label,
        status: a.status,
        phone: a.phone,
        pushName: a.pushName,
        sentToday: a.sentToday,
        dailyLimit: a.dailyLimit,
        isRestricted: a.isRestricted,
        restrictedUntil: a.restrictedUntil,
        hasQr: !!a.qrCodeDataUrl,
      })),
    },
    config,
  });
});

// 2. Lis konplè tout liy WhatsApp yo nan cluster a
app.get('/api/accounts', (req, res) => {
  const accounts = cluster.getAllAccounts().map((a) => ({
    index: a.accountIndex,
    label: a.label,
    status: a.status,
    phone: a.phone,
    pushName: a.pushName,
    qr: a.qrCodeDataUrl,
    rawQr: a.rawQrCode,
    sentToday: a.sentToday,
    dailyLimit: a.dailyLimit,
    lastSentAt: a.lastSentAt ? new Date(a.lastSentAt).toISOString() : null,
    isRestricted: a.isRestricted,
    restrictedUntil: a.restrictedUntil,
    restrictionReason: a.restrictionReason,
    lastError: a.lastError,
  }));
  res.json({ ok: true, accounts });
});

// 3. Rekonekte / Rafrechi QR yon kont espesifik
app.post('/api/accounts/:index/initialize', async (req, res) => {
  const idx = Number(req.params.index);
  const acc = cluster.getAccount(idx);
  if (!acc) return res.status(404).json({ ok: false, error: 'Kont pa jwenn.' });

  try {
    await acc.destroy();
    acc.status = 'DISCONNECTED';
    acc.restrictedUntil = null;
    acc.restrictionReason = null;
    acc.init();
    res.json({ ok: true, message: `Liy ${idx} ap re-inisyalize...` });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// 4. Reyinisyalize (Wipe sesyon) yon kont espesifik
app.post('/api/accounts/:index/reset', async (req, res) => {
  const idx = Number(req.params.index);
  const acc = cluster.getAccount(idx);
  if (!acc) return res.status(404).json({ ok: false, error: 'Kont pa jwenn.' });

  try {
    await acc.destroy();
    try {
      if (fs.existsSync(acc.sessionDir)) {
        fs.rmSync(acc.sessionDir, { recursive: true, force: true });
      }
    } catch (_) {}
    acc.status = 'DISCONNECTED';
    acc.phone = null;
    acc.pushName = null;
    acc.restrictedUntil = null;
    acc.init();
    res.json({ ok: true, message: `Sesyon Liy ${idx} efase nèt. Nouvo QR ap prepare.` });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// 5. Debloke manyèlman yon liy ki te an 24h restriksyon
app.post('/api/accounts/:index/unrestrict', async (req, res) => {
  const idx = Number(req.params.index);
  const acc = cluster.getAccount(idx);
  if (!acc) return res.status(404).json({ ok: false, error: 'Kont pa jwenn.' });

  acc.status = 'DISCONNECTED';
  acc.restrictedUntil = null;
  acc.restrictionReason = null;
  try {
    await fetch(`${SUPABASE_URL}/rest/v1/rpc/platform_whatsapp_account_unrestrict`, {
      method: 'POST',
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p_account_index: idx }),
    });
  } catch (_) {}
  acc.init();
  res.json({ ok: true, message: `Liy ${idx} debloke.` });
});

// 6. Voye mesaj (Backwards compatibility)
app.post('/api/send', async (req, res) => {
  try {
    const { to, message, pdf_base64, pdf_file_name } = req.body;
    const result = await cluster.sendMessageAnywhere(to, message, pdf_base64, pdf_file_name);
    res.json({ ok: true, messageId: result && result.id ? result.id._serialized : null, to });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// 7. Tès voye mesaj
app.post('/api/test', async (req, res) => {
  try {
    const target = req.body.to || config.validNumber;
    const testMsg = req.body.message || `🏋️ *SecurGYM Multi-Kont Cluster*\nMesaj tès distribye avèk siksè !\nDat: ${new Date().toLocaleString()}`;
    const result = await cluster.sendMessageAnywhere(target, testMsg);
    res.json({ ok: true, message: 'Mesaj tès voye avèk siksè !', to: target, messageId: result && result.id ? result.id._serialized : null });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// 8. Cron vérification échéances on-demand
app.post('/api/cron/check-expirations', async (req, res) => {
  try {
    const result = await cluster.runCronExpirationReminders(req.body.gymId || null);
    res.json({ ok: true, result });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// 9. Backwards compatibility: `/api/initialize` ak `/api/reset` pou ansyen UI
app.post('/api/initialize', async (req, res) => {
  const primary = cluster.getAccount(1);
  if (primary) primary.init();
  res.json({ ok: true, message: 'Inisyalizasyon liy prensipal lanse.' });
});
app.post('/api/reset', async (req, res) => {
  const primary = cluster.getAccount(1);
  if (primary) await primary.destroy();
  res.json({ ok: true, message: 'Liy prensipal reyinisyalize.' });
});

// ============================================================================
// LANSE ENTÈVAL BACKGROUND YO
// ============================================================================
// 1. Senkronize lis kont yo soti nan Supabase chak 10s
setInterval(() => cluster.syncAccountsFromSupabase(), 10000);

// 2. Voye heartbeat pou tout kont yo chak 5s
setInterval(() => {
  for (const acc of cluster.accounts.values()) {
    acc.sendHeartbeat();
  }
}, 5000);

// 3. Distribiye mesaj k ap tann nan outbox la chak 3.5s (ak delè moun 25s-50s)
setInterval(() => cluster.dispatchPendingOutboxMessages(), 3500);

// 4. Verifikasyon otomatik rapèl échéance chak 1 èdtan
setInterval(() => cluster.runCronExpirationReminders(), 60 * 60 * 1000);

// Kòmanse sèvè a
app.listen(PORT, '0.0.0.0', async () => {
  console.log('====================================================');
  console.log(`  Sèvis WhatsApp SecurGYM Multi-Kont sou pò ${PORT}`);
  console.log(`  URL Sèvis: http://127.0.0.1:${PORT}`);
  console.log(`  Cloud Bridge Supabase Aktif: ${SUPABASE_URL}`);
  console.log(`  Pwoteksyon Anti-Bann: Delè varyab 25s - 50s + Poz Repo 3 min`);
  console.log('====================================================');

  // Chaje kont yo touswit depi Supabase
  await cluster.syncAccountsFromSupabase();

  // Premye verifikasyon rapèl échéance
  setTimeout(() => cluster.runCronExpirationReminders(), 5000);
});

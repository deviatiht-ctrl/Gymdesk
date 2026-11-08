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

// Dènye vèsyon WhatsApp Web HTML pou evite 'Erreur réessayer plus tard'
let latestWaRemotePath = 'https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/2.3000.1053557623-alpha.html';

async function fetchLatestWaVersion() {
  try {
    const res = await fetch('https://api.github.com/repos/wppconnect-team/wa-version/contents/html', {
      headers: { 'User-Agent': 'SecurGYM-Cluster' },
    });
    if (res.ok) {
      const files = await res.json();
      if (Array.isArray(files) && files.length > 0) {
        const htmlFiles = files
          .map((f) => f.name)
          .filter((n) => typeof n === 'string' && n.endsWith('.html') && n.startsWith('2.'))
          .sort();
        if (htmlFiles.length > 0) {
          const newest = htmlFiles[htmlFiles.length - 1];
          latestWaRemotePath = 'https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/' + newest;
          console.log('[WaVersion] Dènye vèsyon WhatsApp Web detekte:', newest);
        }
      }
    }
  } catch (e) {
    console.warn('[WaVersion] N ap itilize fallback vèsyon WhatsApp:', latestWaRemotePath);
  }
}
fetchLatestWaVersion();
setInterval(fetchLatestWaVersion, 6 * 3600 * 1000);

// Paramèt Delè Sekirite Anti-Spam & Anti-Bann (Human Pacing Entèlijan)
const PACING_CONFIG = {
  // Tranzaksyonèl Priyoritè (Enskripsyon & Renouvèlman & Resi & Tès):
  // Dwe ale rapid touswit pou manm lan pa tann nan sal la! (5s a 15s)
  priorityMinDelayMs: 5000,          // 5 segonn minimòm
  priorityJitterMs: 10000,           // + 0 a 10s varyab (total 5s a 15s)

  // Rapèl Abònman Frèt (7j, 2j, Échéance, Ekspire):
  // Pase dousman chak 10 a 16 minit sou 24h pou anpeche bot ban Meta
  reminderMinDelayMs: 600000,        // 10 minit minimòm
  reminderJitterMs: 360000,          // + 0 a 6 minit varyab (total 10 a 16 minit)

  // Similasyon moun k ap tape tèks la
  typingDelayMinMs: 2500,            // 2.5 segonn
  typingDelayMaxMs: 4500,            // 4.5 segonn

  // Poz repo apre 5 mesaj rapèl konsekitif
  batchPauseAfterCount: 5,
  batchPauseDurationMs: 600000,      // Poz 10 minit (aplike SÈLMAN sou rapèl frèt)

  defaultReminderDailyLimit: 25,     // SÈLMAN rapèl frèt ki limite a 25 pa jou
  maxTransactionalDailyLimit: 200,   // Enskripsyon & Renouvèlman PA GEN LIMIT 25 LA (lib jiska 200/jou)
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
function killOrphanedBrowserForAccount(accountIndex) {
  try {
    const pattern = "*account_" + accountIndex + "*";
    const psScript = "Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'msedge.exe' -or $_.Name -eq 'chrome.exe') -and $_.CommandLine -like '" + pattern + "' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }";
    execSync('powershell -NoProfile -Command "' + psScript + '"', { stdio: 'ignore' });
  } catch (_) {}
}

function cleanEntireSessionDir(sessionDirPath) {
  try {
    if (fs.existsSync(sessionDirPath)) {
      fs.rmSync(sessionDirPath, { recursive: true, force: true });
    }
  } catch (_) {}
}

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

// ============================================================================
// PWOTEKSYON ANTI-SPAM & ANTI-BANN META (Zero Duplicate Hashes & Spintax)
// ============================================================================
function applySpintaxAndHashShield(message) {
  if (!message || typeof message !== 'string') return message;

  let text = message;

  // 1. Varyasyon fòmil salitasyon
  const greetings = ['Bonjour', 'Salut', 'Bonsoir', 'Cher(e) membre', 'Salitasyon'];
  text = text.replace(/^(Bonjour|Salut|Bonsoir|Cher\(e\) membre|Salitasyon)/i, () => {
    return greetings[Math.floor(Math.random() * greetings.length)];
  });

  // 2. Varyasyon Emojis pou evite menm anprent vizyèl
  const reminderIcons = ['⏳', '🔔', '📢', '⚠️', '⚡', '🏋️'];
  text = text.replace(/[⏳🔔📢⚠️⚡]/g, () => {
    return reminderIcons[Math.floor(Math.random() * reminderIcons.length)];
  });

  // 3. Fòmil Envitasyon pou Repons "OK" (Anti-Signalement Spam)
  // Lè kliyan an reponn menm "OK", Meta retire nimewo a nan lis sispèk
  if (text.includes('Ne répondez pas')) {
    text = text.replace(
      /Ne répondez pas à ce (numéro|message)[^.]*\./gi,
      '💡 Pour confirmer la bonne réception et conserver vos accès, répondez simplement "OK" à ce message.'
    );
  }

  // 4. Hash Shield: Enjekte espas envizib Unicode (Zero-Width Space \u200B / \u200C)
  // Sa fè ke CHAK GRENN MESAJ gen yon anprent SHA-256 diferan nèt,
  // konsa filtè WhatsApp pa ka janm detekte se menm mesaj ki repete!
  const zeroWidths = ['\u200B', '\u200C', '\u200D', ''];
  const words = text.split(' ');
  const variated = words.map((w, idx) => {
    if (idx % 3 === 0) {
      const zw = zeroWidths[Math.floor(Math.random() * zeroWidths.length)];
      return w + zw;
    }
    return w;
  }).join(' ');

  return variated;
}

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
    this.reminderDailyLimit = 25; // SÈLMAN rapèl frèt ki limite a 25/jou!
    this.client = null;
    this.status = 'DISCONNECTED';
    this.rawQrCode = null;
    this.qrCodeDataUrl = null;
    this.phone = null;
    this.pushName = null;
    this.lastError = null;
    this.isInitializing = false;
    this.isBusy = false;
    this.lastSentAt = 0;
    this.sentToday = 0;
    this.sentRemindersToday = 0;
    this.sentTransactionalToday = 0;
    this.consecutiveSentCount = 0;
    this.restrictedUntil = null;
    this.restrictionReason = null;
    this.sessionDir = path.join(AUTH_DIR, `session-account_${accountIndex}`);
  }

  get isReady() {
    return (
      this.status === 'READY' &&
      Boolean(this.phone) &&
      this.client !== null &&
      this.client.pupPage !== null &&
      this.client.pupPage !== undefined &&
      typeof this.client.pupPage.isClosed === 'function' &&
      !this.client.pupPage.isClosed() &&
      !this.isRestricted
    );
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

  // Tcheke si kont sa a ka pran yon nouvo mesaj kounye a dapre kalite mesaj la
  canSendNow(messageKind = 'reminder') {
    if (!this.isReady) return false;
    if (this.isBusy) return false;

    // SÈLMAN resi peman renouvèlman/enskripsyon, byenvini, ak tès admin ki tranzaksyonèl priyorite!
    const isPriority = ['receipt', 'welcome', 'test'].includes(messageKind);

    // 1. LIMIT KANTITE PA JOU (Daily Quota):
    if (!isPriority) {
      // SÈLMAN rapèl abònman (cold reminders) ki limite a 25 pa jou pou pwoteje kont lan!
      const limit = this.reminderDailyLimit || PACING_CONFIG.defaultReminderDailyLimit || 25;
      if (this.sentRemindersToday >= limit) {
        return false; // Limit 25 rapèl frèt rive pou jounen an sou liy sa a!
      }
    } else {
      // Enskripsyon ak Renouvèlman se PRIYORITE ABSOLI: YO PA GEN LIMIT 25 LA!
      if (this.sentTransactionalToday >= PACING_CONFIG.maxTransactionalDailyLimit) {
        return false;
      }
    }

    const now = Date.now();

    // 2. DELÈ SEKIRITE ENTÈLIJAN SOU RAPÈL FRÈT (10 a 16 minit):
    if (!isPriority) {
      // 10 a 16 minit ant chak rapèl! Si liy lan te voye yon mesaj deja (lastReminderSentAt oswa lastSentAt), respekte delè a!
      const lastSentTime = Math.max(this.lastReminderSentAt || 0, this.lastSentAt || 0);
      if (lastSentTime > 0) {
        const requiredReminderDelay = PACING_CONFIG.reminderMinDelayMs + (this._nextReminderJitter || 0);
        if (now - lastSentTime < requiredReminderDelay) {
          return false; // Fòk 10 a 16 minit pase nèt anvan pwochen rapèl la!
        }
      }

      // Poz repo apre 5 rapèl
      if (this.consecutiveSentCount >= PACING_CONFIG.batchPauseAfterCount) {
        if (now - (this.lastReminderSentAt || this.lastSentAt) < PACING_CONFIG.batchPauseDurationMs) {
          return false; // Poz 10 minit repo apre 5 rapèl
        } else {
          this.consecutiveSentCount = 0;
        }
      }
    } else {
      // Mesaj tranzaksyonèl (Enskripsyon / Renouvèlman / Resi / Tès): Rapid (5s a 15s)
      if (this.lastSentAt && this.lastSentAt > 0) {
        const requiredPriorityDelay = PACING_CONFIG.priorityMinDelayMs + Math.floor(Math.random() * PACING_CONFIG.priorityJitterMs);
        if (now - this.lastSentAt < requiredPriorityDelay) {
          return false;
        }
      }
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

    // Fèmen ansyen kliyan si l te egziste pou evite konfli sou menm sesyon
    if (this.client) {
      try {
        await this.destroy();
      } catch (_) {}
    }

    this.status = 'INITIALIZING';
    this.lastError = null;
    this.sendHeartbeat();

    console.log(`[Liy ${this.accountIndex} - ${this.label}] Demaraj sesyon WhatsApp...`);

    try {
      killOrphanedBrowserForAccount(this.accountIndex);
      cleanSessionLockFiles(this.sessionDir);
      const execPath = getBrowserExecutablePath();

      this.client = new Client({
        authStrategy: new LocalAuth({
          clientId: `account_${this.accountIndex}`,
          dataPath: AUTH_DIR,
        }),
        webVersionCache: {
          type: 'remote',
          remotePath: latestWaRemotePath,
        },
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        puppeteer: {
          headless: 'new',
          args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-gpu',
            '--no-first-run',
            '--no-default-browser-check',
            '--disable-extensions',
            '--disable-blink-features=AutomationControlled',
            '--disable-features=Translate,OptimizationHints,MediaRouter',
            '--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
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
        try {
          if (this.client && this.client.info) {
            this.phone = this.client.info.wid ? this.client.info.wid.user : null;
            this.pushName = this.client.info.pushname || null;
          }
        } catch (_) {}

        if (!this.phone) {
          console.warn(`[Liy ${this.accountIndex}] 'ready' resevwa men nimewo telefòn nan poko disponib. N ap tann...`);
          setTimeout(async () => {
            try {
              if (this.client && this.client.info && this.client.info.wid) {
                this.phone = this.client.info.wid.user;
                this.pushName = this.client.info.pushname || null;
                this.status = 'READY';
                this.isInitializing = false;
                this.lastError = null;
                console.log(`[Liy ${this.accountIndex}] ✅ Konekte kòm: ${this.pushName || 'Enkoni'} (${this.phone})`);
                this.sendHeartbeat();
              }
            } catch (_) {}
          }, 2000);
          return;
        }

        console.log(`[Liy ${this.accountIndex}] ✅ Kliyan WhatsApp pare nèt pou voye mesaj! Konekte kòm: ${this.pushName || 'Enkoni'} (${this.phone})`);
        this.status = 'READY';
        try { await this.ensureInjected(); } catch (_) {}
        this.isInitializing = false;
        this.lastError = null;
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

  // Asire ke kòd entèn WWebJS ak getChat disponib nan kontèks paj Puppeteer la
  async ensureInjected() {
    if (!this.client || !this.client.pupPage || this.client.pupPage.isClosed()) {
      throw new Error(`Navigatè pou Liy ${this.accountIndex} pa pare.`);
    }

    // Maske navigator.webdriver pou Meta pa detekte ke se yon bot
    try {
      await this.client.pupPage.evaluate(() => {
        try {
          Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
          if (!window.chrome) window.chrome = { runtime: {} };
          Object.defineProperty(navigator, 'languages', { get: () => ['fr-FR', 'fr', 'en-US', 'en'] });
        } catch (_) {}
      });
    } catch (_) {}

    let isReady = false;
    try {
      isReady = await this.client.pupPage.evaluate(() => {
        return Boolean(
          typeof window.WWebJS !== 'undefined' &&
          typeof window.WWebJS.getChat === 'function' &&
          typeof window.WWebJS.sendMessage === 'function'
        );
      });
    } catch (_) {}

    if (isReady) return true;

    console.log(`[Liy ${this.accountIndex}] 🔄 window.WWebJS pa pare nan paj la. Re-injeksyon LoadUtils...`);
    try {
      const { LoadUtils } = require('whatsapp-web.js/src/util/Injected/Utils');
      const { ExposeAuthStore } = require('whatsapp-web.js/src/util/Injected/AuthStore/AuthStore');
      await this.client.pupPage.evaluate(ExposeAuthStore).catch(() => {});
      await this.client.pupPage.evaluate(LoadUtils).catch(() => {});
      await new Promise((r) => setTimeout(r, 400));
    } catch (e) {
      console.warn(`[Liy ${this.accountIndex}] ensureInjected erè:`, e.message);
    }

    try {
      isReady = await this.client.pupPage.evaluate(() => {
        return Boolean(
          typeof window.WWebJS !== 'undefined' &&
          typeof window.WWebJS.getChat === 'function' &&
          typeof window.WWebJS.sendMessage === 'function'
        );
      });
    } catch (_) {}

    return isReady;
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
  async sendWithHumanPresence(chatId, content, options = {}, outboxId = null, messageKind = 'reminder') {
    if (!this.isReady) {
      throw new Error(`Liy ${this.accountIndex} pa pare oswa li restreint.`);
    }

    this.isBusy = true;
    try {
      // 1. Asire kòd WWebJS byen enjekte nan paj la anvan nenpòt aksyon
      await this.ensureInjected();

      // 2. Voye siyal prezans "Online"
      try { await this.client.sendPresenceAvailable(); } catch (_) {}

      // 3. Simile yon moun k ap tape tèks la
      try {
        await this.client.pupPage.evaluate((cid) => {
          if (window.WWebJS && typeof window.WWebJS.sendChatstate === 'function') {
            window.WWebJS.sendChatstate('typing', cid);
          }
        }, chatId);
      } catch (_) {}
      const typingMs = PACING_CONFIG.typingDelayMinMs + Math.floor(Math.random() * (PACING_CONFIG.typingDelayMaxMs - PACING_CONFIG.typingDelayMinMs));
      await new Promise((r) => setTimeout(r, typingMs));

      // 3. Voye mesaj la
      let res;
      try {
        const finalContent = typeof content === 'string' ? applySpintaxAndHashShield(content) : content;
      const finalOptions = { ...options };
      if (finalOptions.caption && typeof finalOptions.caption === 'string') {
        finalOptions.caption = applySpintaxAndHashShield(finalOptions.caption);
      }
      res = await this.client.sendMessage(chatId, finalContent, finalOptions);
      } catch (sendErr) {
        const errMsg = String(sendErr && sendErr.message ? sendErr.message : sendErr);
        if (errMsg.includes('getChat') || errMsg.includes('WWebJS')) {
          console.warn(`[Liy ${this.accountIndex}] Erè getChat detekte, re-injeksyon kòd epi re-eseye...`);
          try {
            await this.ensureInjected();
            res = await this.client.sendMessage(chatId, content, options);
          } catch (retryErr) {
            throw retryErr;
          }
        } else if (errMsg.includes('evaluate') || errMsg.includes('Target closed') || errMsg.includes('Session closed')) {
          console.warn(`[Liy ${this.accountIndex}] Navigatè a te kraze: ${errMsg}. N ap relanse l...`);
          this.status = 'DISCONNECTED';
          this.sendHeartbeat();
          setTimeout(() => this.init(), 1500);
        } else if (errMsg.includes('401') || errMsg.includes('403') || errMsg.includes('rate-overlimit') || errMsg.includes('restricted')) {
          await this.markRestricted(24, errMsg);
          throw new Error(`Nimewo a fètke resevwa restriksyon pa WhatsApp: ${errMsg}`);
        }
        throw sendErr;
      }

      // 4. Kanpe siyal k ap tape epi remete siyal prezans nòmal
      try {
        await this.client.pupPage.evaluate((cid) => {
          if (window.WWebJS && typeof window.WWebJS.sendChatstate === 'function') {
            window.WWebJS.sendChatstate('stop', cid);
          }
        }, chatId);
      } catch (_) {}
      try { await this.client.sendPresenceAvailable(); } catch (_) {}

      // 5. Mete ajou statistik lokal ak Supabase
      this.lastSentAt = Date.now();
      this.sentToday += 1;

      const isPriority = ['receipt', 'welcome', 'test'].includes(messageKind);
      if (isPriority) {
        this.sentTransactionalToday += 1;
        this.lastTransactionalSentAt = Date.now();
        console.log(`[Liy ${this.accountIndex} - ${this.phone || this.label}] ⚡ Mesaj tranzaksyonèl priyorite voye bay ${chatId}.`);
      } else {
        this.sentRemindersToday += 1;
        this.consecutiveSentCount += 1;
        this.lastReminderSentAt = Date.now();
        this._nextReminderJitter = Math.floor(Math.random() * PACING_CONFIG.reminderJitterMs);
        const waitMin = ((PACING_CONFIG.reminderMinDelayMs + this._nextReminderJitter) / 60000).toFixed(1);
        console.log(`[Liy ${this.accountIndex} - ${this.phone || this.label}] ⏳ Rapèl abònman voye bay ${chatId} (${this.sentRemindersToday}/${this.reminderDailyLimit || 25} jodi a). Pwochen rapèl ap tann ${waitMin} minit.`);
      }

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

            // 1. Kòmand aksyon depi Cloud Bridge (Web / Tablet)
            if (row.service_status === 'RESET_REQUESTED') {
              console.log("[Liy " + idx + "] 🔄 Demann Reyinisyalizasyon (Wipe) depi Cloud Bridge.");
              instance.destroy().then(() => {
                cleanEntireSessionDir(instance.sessionDir);
                instance.status = 'DISCONNECTED';
                instance.phone = null;
                instance.pushName = null;
                instance.lastError = null;
                instance.rawQrCode = null;
                instance.qrCodeDataUrl = null;
                instance.init();
              });
              continue;
            } else if (row.service_status === 'RESTART_REQUESTED') {
              console.log("[Liy " + idx + "] 🔄 Demann Rekoneksyon / Rafrechi depi Cloud Bridge.");
              instance.destroy().then(() => {
                instance.status = 'DISCONNECTED';
                instance.lastError = null;
                instance.rawQrCode = null;
                instance.qrCodeDataUrl = null;
                instance.init();
              });
              continue;
            }

            // 2. Si kont lan make RESTREINT nan baz done a
            if (row.service_status === 'RESTRICTED' && row.restricted_until) {
              instance.status = 'RESTRICTED';
              instance.restrictedUntil = row.restricted_until;
              instance.restrictionReason = row.restriction_reason;
            }

            // 3. Si kont lan make aktif men li poko lanse (DISCONNECTED oswa ERROR) epi li pa restreint
            if (row.is_enabled && !instance.isRestricted && (instance.status === 'DISCONNECTED' || instance.status === 'ERROR') && !instance.isInitializing && !instance.client) {
              setTimeout(() => instance.init(), (idx % 3) * 3000);
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
  getNextAvailableAccount(messageKind = 'reminder') {
    const readyAccounts = this.getAllAccounts().filter((acc) => acc.canSendNow(messageKind));
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
      let item = null;
      let assignedAccount = null;

      // 1. Chèche mesaj tranzaksyonèl priyoritè an premye (Enskripsyon / Renouvèlman / Resi: 3 a 5 minit)
      const priorityUrl = `${SUPABASE_URL}/rest/v1/whatsapp_messages_outbox?status=eq.pending&kind=in.(receipt,welcome,test)&order=created_at.asc&limit=1`;
      const pRes = await fetch(priorityUrl, {
        method: 'GET',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
        },
      });

      if (pRes.ok) {
        const pMessages = await pRes.json();
        if (Array.isArray(pMessages) && pMessages.length > 0) {
          const candidateAcc = this.getNextAvailableAccount('receipt');
          if (candidateAcc) {
            item = pMessages[0];
            assignedAccount = candidateAcc;
          }
        }
      }

      // 2. Si pa gen mesaj priyoritè pare, tcheke rapèl abònman (chak 8 a 12 minit, mwayèn 10 minit)
      if (!item) {
        const candidateReminderAcc = this.getNextAvailableAccount('reminder');
        if (candidateReminderAcc) {
          const reminderUrl = `${SUPABASE_URL}/rest/v1/whatsapp_messages_outbox?status=eq.pending&kind=not.in.(receipt,welcome,test)&order=created_at.asc&limit=1`;
          const rRes = await fetch(reminderUrl, {
            method: 'GET',
            headers: {
              'apikey': SUPABASE_ANON_KEY,
              'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
            },
          });
          if (rRes.ok) {
            const rMessages = await rRes.json();
            if (Array.isArray(rMessages) && rMessages.length > 0) {
              item = rMessages[0];
              assignedAccount = candidateReminderAcc;
            }
          }
        }
      }

      if (!item || !assignedAccount) {
        // Okenn mesaj oswa okenn liy pa nan entèval tan pou voye kounye a
        return;
      }

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
        const msgKind = ['receipt', 'welcome', 'test'].includes(item.kind) ? item.kind : 'reminder';
        let sendResult;
        if (item.pdf_base64 && typeof item.pdf_base64 === 'string') {
          try {
            const media = new MessageMedia('application/pdf', item.pdf_base64, item.pdf_file_name || 'Recu.pdf');
            sendResult = await assignedAccount.sendWithHumanPresence(chatId, media, { caption: item.message.trim() }, item.id, msgKind);
          } catch (_) {
            sendResult = await assignedAccount.sendWithHumanPresence(chatId, item.message.trim(), {}, item.id, msgKind);
          }
        } else {
          sendResult = await assignedAccount.sendWithHumanPresence(chatId, item.message.trim(), {}, item.id, msgKind);
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
        assignedAccount.lastSentAt = Date.now();
        const retries = (item.retry_count || 0) + 1;
        const newStatus = retries >= 5 ? 'failed' : 'pending';
        await fetch(`${SUPABASE_URL}/rest/v1/whatsapp_messages_outbox?id=eq.${item.id}`, {
          method: 'PATCH',
          headers: {
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            status: newStatus,
            error_message: `Echwe sou Liy ${assignedAccount.accountIndex} (${sendErr.message}); ${retries >= 5 ? 'abandone apre 5 tantativ' : 'ap re-eseye sou yon lòt liy'}`,
            retry_count: retries,
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

    // Tann jiska 5 segonn si gen yon liy ki pare men ki okipe ap fini voye yon lòt mesaj
    let chosen = null;
    for (let attempt = 0; attempt < 10; attempt++) {
      const readyAccounts = this.getAllAccounts().filter((a) => a.isReady && !a.isBusy);
      if (readyAccounts.length > 0) {
        readyAccounts.sort((a, b) => a.lastSentAt - b.lastSentAt);
        chosen = readyAccounts[0];
        break;
      }
      const hasAnyReady = this.getAllAccounts().some((a) => a.isReady);
      if (!hasAnyReady) {
        break;
      }
      await new Promise((r) => setTimeout(r, 500));
    }

    if (!chosen) {
      throw new Error('Okenn liy WhatsApp pa pare oswa konekte pou voye mesaj kounye a.');
    }

    if (mediaBase64) {
      const media = new MessageMedia('application/pdf', mediaBase64, mediaName || 'Document.pdf');
      return await chosen.sendWithHumanPresence(chatId, media, { caption: message.trim() }, null, 'receipt');
    } else {
      return await chosen.sendWithHumanPresence(chatId, message.trim(), {}, null, 'test');
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
  const readyAccount = accounts.find((a) => a.isReady);
  const primary = accounts[0] || null;
  const activeRep = readyAccount || primary;

  res.json({
    ok: true,
    status: readyCount > 0 ? 'READY' : (primary ? primary.status : 'DISCONNECTED'),
    phone: activeRep ? activeRep.phone : null,
    pushname: activeRep ? activeRep.pushName : null,
    qr: activeRep ? activeRep.qrCodeDataUrl : null,
    rawQr: activeRep ? activeRep.rawQrCode : null,
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
    id: 'account_' + a.accountIndex,
    account_index: a.accountIndex,
    index: a.accountIndex,
    label: a.label,
    service_status: a.status,
    status: a.status,
    phone_number: a.phone,
    phone: a.phone,
    push_name: a.pushName,
    pushName: a.pushName,
    qr_code: a.qrCodeDataUrl,
    qr: a.qrCodeDataUrl,
    rawQr: a.rawQrCode,
    sent_today: a.sentToday,
    sentToday: a.sentToday,
    daily_limit: a.dailyLimit,
    dailyLimit: a.dailyLimit,
    total_sent: 0,
    is_online: true,
    is_enabled: true,
    last_sent_at: a.lastSentAt ? new Date(a.lastSentAt).toISOString() : null,
    is_restricted: a.isRestricted,
    restricted_until: a.restrictedUntil,
    restriction_reason: a.restrictionReason,
    last_error: a.lastError,
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
    cleanEntireSessionDir(acc.sessionDir);
    acc.status = 'DISCONNECTED';
    acc.phone = null;
    acc.pushName = null;
    acc.rawQrCode = null;
    acc.qrCodeDataUrl = null;
    acc.lastError = null;
    acc.restrictedUntil = null;
    acc.init();
    res.json({ ok: true, message: "Sesyon Liy " + idx + " efase nèt. Nouvo QR ap prepare." });
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
app.post(['/api/test', '/api/test-message'], async (req, res) => {
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

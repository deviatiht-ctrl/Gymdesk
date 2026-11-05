const express = require('express');
const cors = require('cors');
const qrcode = require('qrcode');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');

// Pwoteje pwosesis la kont erè CDP / Network ki ka soti nan Puppeteer
process.on('unhandledRejection', (reason) => {
  console.warn('[WhatsApp] Intercepted unhandledRejection:', reason && reason.message ? reason.message : reason);
});
process.on('uncaughtException', (err) => {
  console.warn('[WhatsApp] Intercepted uncaughtException:', err && err.message ? err.message : err);
});

const PORT = process.env.PORT || 47812;
const CONFIG_FILE = path.join(__dirname, 'config.json');
const AUTH_DIR = path.join(__dirname, '.wwebjs_auth');

// Supabase Cloud Bridge Config (pou Tablet, Telefòn, ak Web)
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://jrhdegdvdqnxstpdzbya.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpyaGRlZ2R2ZHFueHN0cGR6YnlhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEyOTM2NDksImV4cCI6MjEwNjg2OTY0OX0.O8WMsF2z447mdWj6gNMyaJ9Q8eTFQwKZyLMMsxrfx5Y';

// 1. Chaje konfigirasyon lokal la
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
    } else {
      saveConfig();
    }
  } catch (err) {
    console.error('[Config] Erè lè n ap li config.json:', err.message);
  }
}

function saveConfig() {
  try {
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2), 'utf8');
  } catch (err) {
    console.error('[Config] Erè lè n ap anrejistre config.json:', err.message);
  }
}

loadConfig();

// 2. Chèche chemen Chrome oswa Edge sou Windows pou Puppeteer
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
    if (fs.existsSync(p)) {
      return p;
    }
  }
  return undefined;
}

// 3. Fèmen nenpòt pwosesis zonbi Edge / Chrome ki kenbe lock sou sesyon an
function killOrphanedEdgeProcesses() {
  try {
    execSync(
      'powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \\"Name = \'msedge.exe\'\\" | Where-Object { $_.CommandLine -like \'*whatsapp_service*\' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"',
      { stdio: 'ignore' }
    );
  } catch (_) {}
}

// 4. Netwaye fichye LOCK yo pou evite "The browser is already running"
function cleanLockFiles(dirPath) {
  try {
    if (!fs.existsSync(dirPath)) return;
    const items = fs.readdirSync(dirPath, { withFileTypes: true });
    for (const item of items) {
      const fullPath = path.join(dirPath, item.name);
      if (item.isDirectory()) {
        cleanLockFiles(fullPath);
      } else {
        const nameLower = item.name.toLowerCase();
        if (
          nameLower === 'singletonlock' ||
          nameLower === 'singletoncookie' ||
          nameLower === 'singletonsocket' ||
          nameLower === 'devtoolsactiveport' ||
          nameLower === 'lock'
        ) {
          try {
            fs.unlinkSync(fullPath);
            console.log(`[WhatsApp] Fichye lock retire: ${item.name}`);
          } catch (_) {}
        }
      }
    }
  } catch (err) {
    console.warn('[WhatsApp] Pa ka netwaye lock files:', err.message);
  }
}

// Eta sèvis WhatsApp la
let client = null;
let clientStatus = 'DISCONNECTED'; // DISCONNECTED | INITIALIZING | SCAN_QR | AUTHENTICATED | READY | ERROR
let rawQrCode = null;
let qrDataUrl = null;
let connectedUser = null;
let pushName = null;
let lastError = null;
let isInitializing = false;
let disconnectedSince = null;

// Anti-Spam Message Queue pou evite WhatsApp bloke nimewo a
const messageQueue = [];
let isProcessingQueue = false;

async function processMessageQueue() {
  if (isProcessingQueue || messageQueue.length === 0) return;
  isProcessingQueue = true;

  while (messageQueue.length > 0) {
    const task = messageQueue.shift();
    try {
      const result = await task.action();
      task.resolve(result);
    } catch (err) {
      task.reject(err);
    }

    // Delè sekirite anti-spam ant chak mesaj (2000 a 3500 milisegonn)
    if (messageQueue.length > 0) {
      const delayMs = 2000 + Math.floor(Math.random() * 1500);
      console.log(`[Anti-Spam] Delè sekirite: ${delayMs}ms ant mesaj...`);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }

  isProcessingQueue = false;
}

function enqueueMessage(action) {
  return new Promise((resolve, reject) => {
    messageQueue.push({ action, resolve, reject });
    processMessageQueue();
  });
}

// Detwi kliyan an avèk sekirite epi libere tout resous
async function destroyCurrentClient() {
  if (client) {
    try {
      console.log('[WhatsApp] N ap fèmen ansyen kliyan Puppeteer...');
      if (client.pupBrowser) {
        const pid = client.pupBrowser.process()?.pid;
        if (pid) {
          try {
            execSync(`taskkill /F /T /PID ${pid}`, { stdio: 'ignore' });
            console.log(`[WhatsApp] Pwosesis browser PID ${pid} fèmen.`);
          } catch (_) {}
        }
      }
      await client.destroy().catch(() => {});
    } catch (e) {
      console.warn('[WhatsApp] Erè pandan destroy():', e.message);
    }
    client = null;
  }
  isInitializing = false;
  killOrphanedEdgeProcesses();
  cleanLockFiles(AUTH_DIR);
}

// Voye mesaj avèk rekiperasyon otomatik si gen "detached Frame" oswa CDP dekonekte
async function safeSendMessage(chatId, content, options) {
  if (!client || clientStatus !== 'READY') {
    throw new Error(`WhatsApp pa konekte (Estati: ${clientStatus}). Eskane kòd QR la sou panèl admin nan.`);
  }

  try {
    return await client.sendMessage(chatId, content, options);
  } catch (err) {
    const errMsg = err && err.message ? err.message : String(err);
    console.warn(`[WhatsApp] Erè sendMessage: ${errMsg}`);

    // Si erè a se detached Frame oswa context destroyed, repare li otomatikman
    if (
      errMsg.includes('detached Frame') ||
      errMsg.includes('Execution context was destroyed') ||
      errMsg.includes('Target closed') ||
      errMsg.includes('Session closed')
    ) {
      console.warn('[WhatsApp] ⚠️ Detached Frame detekte! N ap rafrechi paj WhatsApp la otomatikman...');
      try {
        if (client && client.pupPage) {
          await client.pupPage.reload({ waitUntil: 'networkidle0' }).catch(() => {});
          console.log('[WhatsApp] Paj rafrechi, n ap tann 5s pou WhatsApp Web re-establi...');
          await new Promise((r) => setTimeout(r, 5000));
          console.log(`[WhatsApp] N ap re-eseye voye mesaj la bay ${chatId}...`);
          return await client.sendMessage(chatId, content, options);
        }
      } catch (recoveryErr) {
        console.error('[WhatsApp] Rafrechisman echwe, n ap rekonekte kliyan an:', recoveryErr.message);
        setTimeout(() => {
          destroyCurrentClient().then(() => initWhatsAppClient());
        }, 1000);
        throw new Error('Sistèm WhatsApp la te pèdi koneksyon an entèn; li fèk rekonekte otomatikman. Tanpri re-eseye nan kèk segonn.');
      }
    }
    throw err;
  }
}

async function initWhatsAppClient() {
  if (isInitializing) {
    console.log('[WhatsApp] Inisyalizasyon deja an kou...');
    return;
  }
  isInitializing = true;
  clientStatus = 'INITIALIZING';
  rawQrCode = null;
  qrDataUrl = null;
  lastError = null;
  disconnectedSince = null;

  console.log('[WhatsApp] Demaraj kliyan WhatsApp Web...');

  try {
    killOrphanedEdgeProcesses();
    cleanLockFiles(AUTH_DIR);

    const execPath = getBrowserExecutablePath();
    if (execPath) {
      console.log(`[Puppeteer] Sèvi ak navigatè: ${execPath}`);
    }

    const puppeteerOptions = {
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
    };
    if (execPath) {
      puppeteerOptions.executablePath = execPath;
    }

    client = new Client({
      authStrategy: new LocalAuth({ dataPath: AUTH_DIR }),
      webVersionCache: { type: 'none' },
      puppeteer: puppeteerOptions,
    });

    client.on('qr', async (qr) => {
      console.log('[WhatsApp] Nouvo Kòd QR resevwa. Pare pou eskanè!');
      clientStatus = 'SCAN_QR';
      rawQrCode = qr;
      isInitializing = false;
      disconnectedSince = null;
      try {
        qrDataUrl = await qrcode.toDataURL(qr, { margin: 2, scale: 8 });
        sendSupabaseHeartbeat();
      } catch (err) {
        console.error('[WhatsApp] Erè konvèsyon QR an DataURL:', err.message);
      }
    });

    client.on('authenticated', () => {
      console.log('[WhatsApp] Otantifikasyon reyisi!');
      clientStatus = 'AUTHENTICATED';
      rawQrCode = null;
      qrDataUrl = null;
      lastError = null;
      disconnectedSince = null;
      sendSupabaseHeartbeat();
    });

    client.on('auth_failure', async (msg) => {
      console.error('[WhatsApp] Echèk otantifikasyon:', msg);
      clientStatus = 'ERROR';
      lastError = `Echèk otantifikasyon: ${msg}`;
      isInitializing = false;
      disconnectedSince = Date.now();
      try {
        await destroyCurrentClient();
        fs.rmSync(AUTH_DIR, { recursive: true, force: true });
      } catch (_) {}
      sendSupabaseHeartbeat();
    });

    client.on('ready', async () => {
      console.log('[WhatsApp] Kliyan WhatsApp pare nèt pou voye mesaj!');
      clientStatus = 'READY';
      isInitializing = false;
      lastError = null;
      disconnectedSince = null;
      try {
        if (client && client.info) {
          connectedUser = client.info.wid ? client.info.wid.user : null;
          pushName = client.info.pushname || null;
          console.log(`[WhatsApp] Konekte kòm: ${pushName || 'Enkoni'} (${connectedUser})`);
        }
      } catch (e) {
        console.warn('[WhatsApp] Pa ka li info itilizatè a:', e.message);
      }
      sendSupabaseHeartbeat();
    });

    client.on('disconnected', (reason) => {
      console.warn('[WhatsApp] Kliyan dekonekte:', reason);
      clientStatus = 'DISCONNECTED';
      connectedUser = null;
      pushName = null;
      rawQrCode = null;
      qrDataUrl = null;
      isInitializing = false;
      disconnectedSince = Date.now();
      sendSupabaseHeartbeat();
    });

    client.initialize().catch(async (err) => {
      console.error('[WhatsApp] Erè inisyalizasyon:', err.message);
      clientStatus = 'ERROR';
      lastError = err.message;
      isInitializing = false;
      disconnectedSince = Date.now();
      cleanLockFiles(AUTH_DIR);
      sendSupabaseHeartbeat();
    });
  } catch (err) {
    console.error('[WhatsApp] Erè lansman:', err.message);
    clientStatus = 'ERROR';
    lastError = err.message;
    isInitializing = false;
    disconnectedSince = Date.now();
    cleanLockFiles(AUTH_DIR);
    sendSupabaseHeartbeat();
  }
}

// Netwaye epi mete nimewo a nan fòma WhatsApp entènasyonal (egz: 50937001122)
function cleanPhoneNumber(phone) {
  if (!phone) return null;
  let digits = String(phone).replace(/\D/g, '');
  if (!digits) return null;

  // Si nimewo an gen 8 chif (tankou 37001122), ajoute kòd peyi pa defo a (509)
  const defaultCode = (config.defaultCountryCode || '509').replace(/\D/g, '');
  if (digits.length === 8 && defaultCode) {
    digits = defaultCode + digits;
  }
  return digits;
}

// ============================================================================
// CLOUD BRIDGE SUPABASE: Pou Tablet, Telefòn, ak Web (Vercel)
// ============================================================================
async function sendSupabaseHeartbeat() {
  try {
    await fetch(`${SUPABASE_URL}/rest/v1/rpc/platform_whatsapp_heartbeat`, {
      method: 'POST',
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        p_service_status: clientStatus,
        p_connected_phone: connectedUser,
        p_push_name: pushName,
        p_qr_code: (clientStatus === 'SCAN_QR' ? qrDataUrl : null),
        p_queue_length: messageQueue.length,
        p_last_error: lastError,
      }),
    });
  } catch (_) {
    // ignor network hiccups
  }
}

let isPollingOutbox = false;
async function pollSupabaseOutbox() {
  if (isPollingOutbox) return;
  if (clientStatus !== 'READY' || !client) return;
  isPollingOutbox = true;

  try {
    const url = `${SUPABASE_URL}/rest/v1/whatsapp_messages_outbox?status=eq.pending&order=created_at.asc&limit=5`;
    const res = await fetch(url, {
      method: 'GET',
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
      },
    });

    if (res.ok) {
      const messages = await res.json();
      if (Array.isArray(messages) && messages.length > 0) {
        console.log(`[Cloud Bridge] Resevwa ${messages.length} nouvo mesaj soti nan Supabase (Tablet/Web)...`);
        for (const item of messages) {
          // Mete status kòm processing pou evite lòt worker pran l
          await fetch(`${SUPABASE_URL}/rest/v1/whatsapp_messages_outbox?id=eq.${item.id}`, {
            method: 'PATCH',
            headers: {
              'apikey': SUPABASE_ANON_KEY,
              'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ status: 'processing', processed_at: new Date().toISOString() }),
          });

          // Mete mesaj la nan ke anti-spam lan
          enqueueMessage(async () => {
            const cleanPhone = cleanPhoneNumber(item.to_phone);
            if (!cleanPhone || cleanPhone.length < 8) {
              throw new Error('Nimewo telefòn destinataire a pa valid.');
            }
            const chatId = `${cleanPhone}@c.us`;

            if (item.pdf_base64 && typeof item.pdf_base64 === 'string') {
              try {
                const media = new MessageMedia('application/pdf', item.pdf_base64, item.pdf_file_name || 'Recu.pdf');
                return await safeSendMessage(chatId, media, { caption: item.message.trim() });
              } catch (mediaErr) {
                console.warn('[Cloud Bridge] Erè voye PDF, n ap voye kòm tèks:', mediaErr.message);
                return await safeSendMessage(chatId, item.message.trim());
              }
            } else {
              return await safeSendMessage(chatId, item.message.trim());
            }
          }).then(async () => {
            // Siksè voye
            await fetch(`${SUPABASE_URL}/rest/v1/whatsapp_messages_outbox?id=eq.${item.id}`, {
              method: 'PATCH',
              headers: {
                'apikey': SUPABASE_ANON_KEY,
                'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({ status: 'sent', sent_at: new Date().toISOString() }),
            });
            console.log(`[Cloud Bridge] ✅ Mesaj ${item.id} voye bay ${item.to_phone} avèk siksè!`);
          }).catch(async (sendErr) => {
            // Echèk voye
            await fetch(`${SUPABASE_URL}/rest/v1/whatsapp_messages_outbox?id=eq.${item.id}`, {
              method: 'PATCH',
              headers: {
                'apikey': SUPABASE_ANON_KEY,
                'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({ status: 'failed', error_message: sendErr.message || String(sendErr) }),
            });
            console.warn(`[Cloud Bridge] ❌ Mesaj ${item.id} echwe:`, sendErr.message);
          });
        }
      }
    }
  } catch (_) {
    // Ignor hiccups
  } finally {
    isPollingOutbox = false;
  }
}

// Watchdog pou relanse WhatsApp otomatikman si li rete DISCONNECTED oswa ERROR plis pase 30 segonn
function watchdogAutoRecovery() {
  if (isInitializing) return;
  if ((clientStatus === 'DISCONNECTED' || clientStatus === 'ERROR') && disconnectedSince) {
    const elapsed = Date.now() - disconnectedSince;
    if (elapsed > 30000) {
      console.log('[Watchdog] WhatsApp rete dekonekte plis pase 30s. N ap relanse li otomatikman...');
      disconnectedSince = Date.now();
      destroyCurrentClient().then(() => initWhatsAppClient());
    }
  }
}

// Lanse entèval background yo
setInterval(sendSupabaseHeartbeat, 5000);
setInterval(pollSupabaseOutbox, 3500);
setInterval(watchdogAutoRecovery, 10000);

// Express App
const app = express();
app.use(cors());
app.use(express.json({ limit: '25mb' }));
app.use(express.urlencoded({ extended: true, limit: '25mb' }));

// 1. Health check & Estati jeneral
app.get('/health', (req, res) => {
  res.json({ ok: true, service: 'securgym-whatsapp', status: clientStatus });
});

app.get('/api/status', (req, res) => {
  res.json({
    ok: true,
    status: clientStatus,
    qr: qrDataUrl,
    rawQr: rawQrCode,
    phone: connectedUser,
    pushname: pushName,
    lastError: lastError,
    config: {
      validNumber: config.validNumber,
      backupNumber: config.backupNumber || '',
      defaultCountryCode: config.defaultCountryCode,
      autoSendWelcome: config.autoSendWelcome !== false,
      autoSendReceipts: config.autoSendReceipts !== false,
      autoSendReminders: config.autoSendReminders !== false,
      reminderDaysBefore: config.reminderDaysBefore || 7,
    },
    queueLength: messageQueue.length,
    uptime: process.uptime(),
  });
});

// 2. Imaj QR Code dirèk
app.get('/api/qr.png', async (req, res) => {
  if (clientStatus === 'SCAN_QR' && rawQrCode) {
    res.setHeader('Content-Type', 'image/png');
    qrcode.toFileStream(res, rawQrCode, { margin: 2, scale: 8 });
  } else {
    res.status(404).send('Pa gen okenn kòd QR disponib pou kounye a');
  }
});

// 3. Konfigirasyon (Li / Chanje)
app.get('/api/config', (req, res) => {
  res.json({ ok: true, config });
});

app.post('/api/config', (req, res) => {
  const {
    validNumber,
    backupNumber,
    defaultCountryCode,
    autoSendWelcome,
    autoSendReceipts,
    autoSendReminders,
    reminderDaysBefore
  } = req.body;

  if (validNumber !== undefined) config.validNumber = String(validNumber).trim();
  if (backupNumber !== undefined) config.backupNumber = String(backupNumber).trim();
  if (defaultCountryCode !== undefined) config.defaultCountryCode = String(defaultCountryCode).trim();
  if (autoSendWelcome !== undefined) config.autoSendWelcome = Boolean(autoSendWelcome);
  if (autoSendReceipts !== undefined) config.autoSendReceipts = Boolean(autoSendReceipts);
  if (autoSendReminders !== undefined) config.autoSendReminders = Boolean(autoSendReminders);
  if (reminderDaysBefore !== undefined) config.reminderDaysBefore = parseInt(reminderDaysBefore) || 7;

  saveConfig();
  console.log('[Config] Konfigirasyon mete ajou:', config);
  res.json({ ok: true, message: 'Konfigirasyon anrejistre avèk siksè', config });
});

// 4. Voye Mesaj WhatsApp (avèk Anti-Spam Queue ak sipò PDF dokiman)
app.post('/api/send', async (req, res) => {
  try {
    const { to, message, pdfBase64, pdfFileName } = req.body;

    if (!message || typeof message !== 'string' || !message.trim()) {
      return res.status(400).json({ ok: false, error: 'Mesaj la pa dwe vid.' });
    }

    const cleanPhone = cleanPhoneNumber(to);
    if (!cleanPhone || cleanPhone.length < 8) {
      return res.status(400).json({ ok: false, error: 'Nimewo telefòn destinataire a pa valid.' });
    }

    if (clientStatus !== 'READY' || !client) {
      return res.status(503).json({
        ok: false,
        error: `WhatsApp pa konekte kounye a (Estati: ${clientStatus}). Eskane kòd QR la sou panèl admin nan.`,
      });
    }

    const chatId = `${cleanPhone}@c.us`;

    // Voye atravè Queue Anti-Spam pou kenbe entèval sekirite
    const result = await enqueueMessage(async () => {
      console.log(`[WhatsApp] N ap voye mesaj bay ${chatId}...`);
      if (pdfBase64 && typeof pdfBase64 === 'string') {
        try {
          console.log(`[WhatsApp] N ap tache PDF dokiman (${pdfFileName || 'Recu.pdf'})...`);
          const media = new MessageMedia('application/pdf', pdfBase64, pdfFileName || 'Recu.pdf');
          return await safeSendMessage(chatId, media, { caption: message.trim() });
        } catch (mediaErr) {
          console.warn('[WhatsApp] Erè voye PDF, n ap voye kòm tèks senp:', mediaErr.message);
          return await safeSendMessage(chatId, message.trim());
        }
      } else {
        return await safeSendMessage(chatId, message.trim());
      }
    });

    res.json({
      ok: true,
      messageId: (result && result.id) ? result.id._serialized : null,
      to: cleanPhone,
      timestamp: Date.now(),
    });
  } catch (err) {
    console.error('[WhatsApp] Erè voye mesaj:', err);
    res.status(500).json({ ok: false, error: err.message || 'Echèk voye mesaj' });
  }
});

// 5. Tès Voye Mesaj
app.post('/api/test', async (req, res) => {
  try {
    const target = req.body.to || config.validNumber;
    const testMsg = req.body.message || `🏋️ *SecurGYM / GymDesk*\nSa a se yon mesaj tès WhatsApp voye avèk siksè depi sistèm jesyon gym nan !\nDat: ${new Date().toLocaleString()}`;

    if (!target) {
      return res.status(400).json({
        ok: false,
        error: 'Tanpri antre yon nimewo valid oswa anrejistre li nan panèl admin nan anvan.',
      });
    }

    const cleanPhone = cleanPhoneNumber(target);
    if (!cleanPhone) {
      return res.status(400).json({ ok: false, error: 'Nimewo tès la pa valid.' });
    }

    if (clientStatus !== 'READY' || !client) {
      return res.status(503).json({
        ok: false,
        error: `WhatsApp pa pare (Estati: ${clientStatus}). Tanpri konekte li avèk kòd QR la anvan.`,
      });
    }

    const chatId = `${cleanPhone}@c.us`;
    const result = await enqueueMessage(async () => {
      return await safeSendMessage(chatId, testMsg);
    });

    res.json({
      ok: true,
      message: 'Mesaj tès la voye avèk siksè !',
      to: cleanPhone,
      messageId: (result && result.id) ? result.id._serialized : null,
    });
  } catch (err) {
    console.error('[WhatsApp] Erè tès:', err);
    res.status(500).json({ ok: false, error: err.message });
  }
});

// 6. Rekonekte / Relanse Kliyan an
app.post('/api/initialize', async (req, res) => {
  console.log('[WhatsApp] Demann rekoneksyon / inisyalizasyon resevwa...');
  try {
    await destroyCurrentClient();
    initWhatsAppClient();
    res.json({ ok: true, message: 'Demaraj kliyan WhatsApp lanse...', status: clientStatus });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// 7. Reyinisyalizasyon Konplè (Wipe .wwebjs_auth ak relanse a zewo)
app.post('/api/reset', async (req, res) => {
  console.log('[WhatsApp] Demann reset konplè sesyon resevwa...');
  try {
    await destroyCurrentClient();
    try {
      if (fs.existsSync(AUTH_DIR)) {
        fs.rmSync(AUTH_DIR, { recursive: true, force: true });
        console.log('[WhatsApp] Dosye .wwebjs_auth efase nèt.');
      }
    } catch (e) {
      console.warn('[WhatsApp] Pa ka efase dosye auth nèt:', e.message);
    }
    clientStatus = 'DISCONNECTED';
    connectedUser = null;
    pushName = null;
    rawQrCode = null;
    qrDataUrl = null;
    lastError = null;

    initWhatsAppClient();
    res.json({ ok: true, message: 'Sesyon an reyinisyalize nèt. Nouvo Kòd QR ap prepare.' });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// 7b. Chanje Nimewo WhatsApp (Switch / Add Backup WhatsApp Number)
app.post('/api/switch-account', async (req, res) => {
  console.log('[WhatsApp] Demann chanje nimewo / nouvo kont WhatsApp resevwa...');
  try {
    const { newNumber, backupNumber } = req.body || {};
    if (newNumber) config.validNumber = String(newNumber).trim();
    if (backupNumber) config.backupNumber = String(backupNumber).trim();
    saveConfig();

    await destroyCurrentClient();
    try {
      if (fs.existsSync(AUTH_DIR)) {
        fs.rmSync(AUTH_DIR, { recursive: true, force: true });
        console.log('[WhatsApp] Ansyen sesyon efase pou nouvo koneksyon.');
      }
    } catch (e) {
      console.warn('[WhatsApp] Pa ka efase dosye auth nèt:', e.message);
    }

    clientStatus = 'DISCONNECTED';
    connectedUser = null;
    pushName = null;
    rawQrCode = null;
    qrDataUrl = null;
    lastError = null;

    initWhatsAppClient();
    res.json({
      ok: true,
      message: 'Ansyen nimewo a dekonekte. Nouvo Kòd QR ap prepare pou w eskane ak lòt nimewo a.',
      status: 'INITIALIZING',
    });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// 8. Dekonekte (Logout)
app.post('/api/logout', async (req, res) => {
  try {
    if (client) {
      await client.logout().catch(() => {});
      await destroyCurrentClient();
    }
    clientStatus = 'DISCONNECTED';
    connectedUser = null;
    pushName = null;
    rawQrCode = null;
    qrDataUrl = null;
    isInitializing = false;

    if (req.body && req.body.clearSession) {
      try {
        if (fs.existsSync(AUTH_DIR)) {
          fs.rmSync(AUTH_DIR, { recursive: true, force: true });
        }
      } catch (_) {}
    }

    console.log('[WhatsApp] Sesyon WhatsApp dekonekte.');
    res.json({ ok: true, message: 'WhatsApp dekonekte avèk siksè.' });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// Kòmanse sèvè Express la epi inisyalize WhatsApp
app.listen(PORT, '0.0.0.0', () => {
  console.log(`====================================================`);
  console.log(`  Sèvis WhatsApp SecurGYM ap kouri sou pò ${PORT}`);
  console.log(`  URL Sèvis: http://127.0.0.1:${PORT}`);
  console.log(`  Cloud Bridge Supabase Aktif: ${SUPABASE_URL}`);
  console.log(`====================================================`);

  // Kòmanse WhatsApp otomatikman
  initWhatsAppClient();
});

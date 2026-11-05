const express = require('express');
const cors = require('cors');
const qrcode = require('qrcode');
const fs = require('fs');
const path = require('path');
const { Client, LocalAuth } = require('whatsapp-web.js');

const PORT = process.env.PORT || 47812;
const CONFIG_FILE = path.join(__dirname, 'config.json');
const AUTH_DIR = path.join(__dirname, '.wwebjs_auth');

// 1. Chaje konfigirasyon lokal la
let config = {
  validNumber: '50932986751',
  defaultCountryCode: '509',
  autoSendReceipts: true,
  autoSendReminders: true,
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

// 3. Netwaye fichye LOCK yo pou evite "The browser is already running"
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

// Detwi kliyan an avèk sekirite
async function destroyCurrentClient() {
  if (client) {
    try {
      console.log('[WhatsApp] N ap fèmen ansyen kliyan Puppeteer...');
      await client.destroy();
    } catch (e) {
      console.warn('[WhatsApp] Erè pandan destroy():', e.message);
    }
    client = null;
  }
  isInitializing = false;
  // Netwaye lock files apre kliyan an fin fèmen
  cleanLockFiles(AUTH_DIR);
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

  console.log('[WhatsApp] Demaraj kliyan WhatsApp Web...');

  try {
    // Netwaye nenpòt lock ki te rete
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
      ],
    };
    if (execPath) {
      puppeteerOptions.executablePath = execPath;
    }

    client = new Client({
      authStrategy: new LocalAuth({ dataPath: AUTH_DIR }),
      puppeteer: puppeteerOptions,
    });

    client.on('qr', async (qr) => {
      console.log('[WhatsApp] Nouvo Kòd QR resevwa. Pare pou eskanè!');
      clientStatus = 'SCAN_QR';
      rawQrCode = qr;
      isInitializing = false;
      try {
        qrDataUrl = await qrcode.toDataURL(qr, { margin: 2, scale: 8 });
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
    });

    client.on('auth_failure', async (msg) => {
      console.error('[WhatsApp] Echèk otantifikasyon:', msg);
      clientStatus = 'ERROR';
      lastError = `Echèk otantifikasyon: ${msg}`;
      isInitializing = false;
      // Si otantifikasyon echwe, siye sesyon an pou re-mande QR
      try {
        await destroyCurrentClient();
        fs.rmSync(AUTH_DIR, { recursive: true, force: true });
      } catch (_) {}
    });

    client.on('ready', async () => {
      console.log('[WhatsApp] Kliyan WhatsApp pare nèt pou voye mesaj!');
      clientStatus = 'READY';
      isInitializing = false;
      lastError = null;
      try {
        if (client && client.info) {
          connectedUser = client.info.wid ? client.info.wid.user : null;
          pushName = client.info.pushname || null;
          console.log(`[WhatsApp] Konekte kòm: ${pushName || 'Enkoni'} (${connectedUser})`);
        }
      } catch (e) {
        console.warn('[WhatsApp] Pa ka li info itilizatè a:', e.message);
      }
    });

    client.on('disconnected', (reason) => {
      console.warn('[WhatsApp] Kliyan dekonekte:', reason);
      clientStatus = 'DISCONNECTED';
      connectedUser = null;
      pushName = null;
      rawQrCode = null;
      qrDataUrl = null;
      isInitializing = false;
    });

    client.initialize().catch(async (err) => {
      console.error('[WhatsApp] Erè inisyalizasyon:', err.message);
      clientStatus = 'ERROR';
      lastError = err.message;
      isInitializing = false;

      // Si se te yon erè "browser already running", netwaye locks yo pou pwochen tantativ
      cleanLockFiles(AUTH_DIR);
    });
  } catch (err) {
    console.error('[WhatsApp] Erè lansman:', err.message);
    clientStatus = 'ERROR';
    lastError = err.message;
    isInitializing = false;
    cleanLockFiles(AUTH_DIR);
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

// Express App
const app = express();
app.use(cors());
app.use(express.json());

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
      defaultCountryCode: config.defaultCountryCode,
      autoSendReceipts: config.autoSendReceipts,
      autoSendReminders: config.autoSendReminders,
    },
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
  const { validNumber, defaultCountryCode, autoSendReceipts, autoSendReminders } = req.body;
  if (validNumber !== undefined) config.validNumber = String(validNumber).trim();
  if (defaultCountryCode !== undefined) config.defaultCountryCode = String(defaultCountryCode).trim();
  if (autoSendReceipts !== undefined) config.autoSendReceipts = Boolean(autoSendReceipts);
  if (autoSendReminders !== undefined) config.autoSendReminders = Boolean(autoSendReminders);

  saveConfig();
  console.log('[Config] Konfigirasyon mete ajou:', config);
  res.json({ ok: true, message: 'Konfigirasyon anrejistre avèk siksè', config });
});

// 4. Voye Mesaj WhatsApp
app.post('/api/send', async (req, res) => {
  try {
    const { to, message } = req.body;

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
    console.log(`[WhatsApp] N ap voye mesaj bay ${chatId}...`);

    const result = await client.sendMessage(chatId, message.trim());

    res.json({
      ok: true,
      messageId: result.id ? result.id._serialized : null,
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
    const result = await client.sendMessage(chatId, testMsg);

    res.json({
      ok: true,
      message: 'Mesaj tès la voye avèk siksè !',
      to: cleanPhone,
      messageId: result.id ? result.id._serialized : null,
    });
  } catch (err) {
    console.error('[WhatsApp] Erè tès:', err);
    res.status(500).json({ ok: false, error: err.message });
  }
});

// 6. Rekonekte / Relanse Kliyan an (Asynchrone avèk netwayaj locks)
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
  console.log(`====================================================`);

  // Kòmanse WhatsApp otomatikman
  initWhatsAppClient();
});

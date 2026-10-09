/**
 * Standalone Node.js FSTW F30 Access Control Gateway
 * 
 * Sa pèmèt sal la kouri yon ti sèvis background sou yon mini-PC, sèvè lokal,
 * oswa Raspberry Pi ki konekte sou menm switch/routeur ak FSTW F30 la.
 * 
 * Li koute Supabase Realtime epi li voye kòmand TCP yo sou FSTW F30 (ex: 192.168.1.200:5005).
 */

const net = require('net');
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'YOUR_KEY';
const FSTW_IP = process.env.FSTW_IP || '192.168.1.200';
const FSTW_PORT = parseInt(process.env.FSTW_PORT || '5005', 10);
const GYM_ID = process.env.GYM_ID || '';

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

function sendTcpCommand(payload) {
  return new Promise((resolve, reject) => {
    const client = new net.Socket();
    client.setTimeout(4000);

    client.connect(FSTW_PORT, FSTW_IP, () => {
      const json = JSON.stringify(payload);
      // STX (0x02) + JSON + ETX (0x03) + \n
      const packet = Buffer.concat([
        Buffer.from([0x02]),
        Buffer.from(json, 'utf8'),
        Buffer.from([0x03, 0x0A]),
      ]);
      client.write(packet);
    });

    client.on('data', (data) => {
      client.destroy();
      resolve(data.toString('utf8'));
    });

    client.on('timeout', () => {
      client.destroy();
      resolve('ACK_TIMEOUT');
    });

    client.on('error', (err) => {
      client.destroy();
      reject(err);
    });
  });
}

async function sendUserFingerprint(userId, template, name) {
  try {
    await sendTcpCommand({ cmd: 'set_user', user_id: userId, name, template });
    console.log(`[SYNC SUCCESS] User ID synced to door (${userId} - ${name})`);
  } catch (err) {
    console.error(`[SYNC FAILED] Retrying... (${userId}: ${err.message})`);
  }
}

async function deleteUser(userId) {
  try {
    await sendTcpCommand({ cmd: 'delete_user', user_id: userId });
    console.log(`[SYNC SUCCESS] User ID synced to door (deleted ${userId})`);
  } catch (err) {
    console.error(`[SYNC FAILED] Retrying... (${userId}: ${err.message})`);
  }
}

async function setTemporaryPin(userId, pin, expiresAt) {
  try {
    await sendTcpCommand({ cmd: 'set_temporary_pin', user_id: userId, pin, expires_at: expiresAt });
    console.log(`[SYNC SUCCESS] User ID synced to door (temp pin ${userId})`);
  } catch (err) {
    console.error(`[SYNC FAILED] Retrying... (${userId}: ${err.message})`);
  }
}

console.log(`[FSTW BRIDGE] Starting bridge for GYM: ${GYM_ID || 'ALL'} -> Door: ${FSTW_IP}:${FSTW_PORT}`);

// Koute Realtime
const channel = supabase
  .channel('fstw_bridge_channel')
  .on('postgres_changes', { event: '*', schema: 'public', table: 'members' }, async (payload) => {
    const record = payload.new;
    if (!record || (GYM_ID && record.gym_id !== GYM_ID)) return;

    if (record.status === 'active') {
      if (record.fingerprint_registered && record.fingerprint_template) {
        await sendUserFingerprint(record.id, record.fingerprint_template, `${record.first_name} ${record.last_name}`);
      }
      if (record.temporary_pin && record.pin_expires_at) {
        await setTemporaryPin(record.id, record.temporary_pin, record.pin_expires_at);
      }
    } else if (['expired', 'inactive', 'suspended'].includes(record.status)) {
      await deleteUser(record.id);
    }
  })
  .subscribe();

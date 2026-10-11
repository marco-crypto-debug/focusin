/**
 * FocusIn License Key 簽發 Worker（Cloudflare Workers）
 *
 * 私鑰只存在本 Worker 的 Secret 中，絕不進前端 / 靜態站。
 *
 * 環境變數（Secret）：
 *   LICENSE_SEED   Ed25519 私鑰 seed，raw 32 bytes 的 base64（與 tools/license-keys 相同金鑰對）
 *   ADMIN_KEY      管理員密碼（官網「發 key」區塊用 header x-admin-key 傳入）
 *   LICENSE_PUB    公鑰 raw 32B base64（可選，用於 /verify 輸出一致性）
 *
 * API：
 *   POST /api/license/gen  body {email, months}  header x-admin-key → {key, expiry, email}
 *   GET  /api/license/verify?key=... → {valid, status, expiry}
 *   GET  /api/license/pub → {pubKeyB64}（供前端 verify 用，公鑰可公開）
 *   GET  /api/license/list  header x-admin-key → 簽發記錄後台（email / key / expiry / 狀態）
 */
import { createPrivateKey, createPublicKey, sign, verify } from 'node:crypto';

const PKCS8_PREFIX = Buffer.from('302e020100300506032b657004220420', 'hex');

function b64url(buf) { return Buffer.from(buf).toString('base64url'); }
function fromB64url(s) {
  let b = s.replace(/-/g, '+').replace(/_/g, '/');
  while (b.length % 4) b += '=';
  return Buffer.from(b, 'base64');
}

/** 到期日：N 個月後的 1 號（每月 1 號繳費制） */
function expiryAfterMonths(months) {
  const d = new Date();
  d.setDate(1);
  d.setMonth(d.getMonth() + months);
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-01';
}

function privateKeyFromSeed() {
  const seed = fromB64url(env().LICENSE_SEED);
  if (seed.length !== 32) throw new Error('LICENSE_SEED 必須是 32 bytes base64');
  // seed → PKCS8 DER（ed25519 結構固定）
  const der = Buffer.concat([PKCS8_PREFIX, seed]);
  return createPrivateKey({ key: der, format: 'der', type: 'pkcs8' });
}

// Workers 上 env 只能從 fetch handler 取得，用閉包暫存
let _env = null;
function env() { return _env; }

export default {
  async fetch(request, envArg) {
    _env = envArg;
    const url = new URL(request.url);
    const path = url.pathname;

    // CORS
    const cors = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, x-admin-key',
    };
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }

    try {
      if (request.method === 'POST' && path === '/api/license/gen') {
        return await genKey(request, cors);
      }
      if (request.method === 'GET' && path === '/api/license/verify') {
        return await verifyKey(url, cors);
      }
      if (request.method === 'GET' && path === '/api/license/pub') {
        return json({ pubKeyB64: env().LICENSE_PUB || '' }, cors);
      }
      if (request.method === 'GET' && path === '/api/license/list') {
        return await listKeys(request, cors);
      }
      return json({ error: 'not found' }, { ...cors }, 404);
    } catch (e) {
      return json({ error: 'server error', detail: String(e) }, { ...cors }, 500);
    }
  },
};

async function genKey(request, cors) {
  // 管理員保護
  const admin = request.headers.get('x-admin-key') || '';
  if (!env().ADMIN_KEY || admin !== env().ADMIN_KEY) {
    return json({ error: 'forbidden' }, { ...cors }, 403);
  }
  let body;
  try { body = await request.json(); } catch { body = {}; }
  const email = String(body.email || '').trim().toLowerCase();
  const months = parseInt(body.months, 10);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ error: 'invalid email' }, { ...cors }, 400);
  }
  if (!(months >= 1 && months <= 36)) {
    return json({ error: 'months 必須在 1~36' }, { ...cors }, 400);
  }
  const expiry = expiryAfterMonths(months);
  const payload = JSON.stringify({ e: email, p: 'pro', x: expiry });
  const priv = privateKeyFromSeed();
  const sig = sign(null, Buffer.from(payload), priv);
  const key = `FI-PRO-${b64url(payload)}.${b64url(sig)}`;
  // 存入 KV（後台列表）：k:<email> → 最新一條記錄
  try {
    const record = { email, key, expiry, issuedAt: new Date().toISOString() };
    await env().LICENSE_KV.put(`k:${email}`, JSON.stringify(record));
  } catch (e) {
    // KV 寫入失敗不阻斷簽發，但回傳標記供診斷
    return json({ key, expiry, email, kvWarning: String(e && e.message || e) }, cors);
  }
  return json({ key, expiry, email }, cors);
}

async function listKeys(request, cors) {
  // 管理員保護
  const admin = request.headers.get('x-admin-key') || '';
  if (!env().ADMIN_KEY || admin !== env().ADMIN_KEY) {
    return json({ error: 'forbidden' }, { ...cors }, 403);
  }
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const items = [];
  let cursor;
  do {
    const page = await env().LICENSE_KV.list({ prefix: 'k:', cursor });
    for (const k of page.keys) {
      try {
        const v = JSON.parse(await env().LICENSE_KV.get(k.name));
        if (!v || !v.key) continue;
        const expDate = new Date(v.expiry + 'T00:00:00');
        v.status = today >= expDate ? 'expired' : 'active';
        items.push(v);
      } catch {}
    }
    cursor = page.cursor;
  } while (cursor);
  // 依簽發時間新→舊排序
  items.sort((a, b) => (b.issuedAt || '').localeCompare(a.issuedAt || ''));
  return json({ count: items.length, items }, cors);
}

async function verifyKey(url, cors) {
  const key = (url.searchParams.get('key') || '').trim();
  if (!key) return json({ valid: false, status: 'invalid', reason: 'empty' }, cors);
  const parts = key.split('.');
  if (parts.length !== 2) return json({ valid: false, status: 'invalid', reason: 'format' }, cors);
  const p64 = parts[0].startsWith('FI-PRO-') ? parts[0].slice(7) : parts[0];
  try {
    const payload = fromB64url(p64);
    const sig = fromB64url(parts[1]);
    const pubRaw = fromB64url(env().LICENSE_PUB);
    const pub = createPublicKey({ key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), pubRaw]), format: 'der', type: 'spki' });
    const ok = verify(null, payload, pub, sig);
    if (!ok) return json({ valid: false, status: 'invalid', reason: 'signature' }, cors);
    const obj = JSON.parse(payload.toString('utf8'));
    const expiry = obj.x;
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const expDate = new Date(expiry + 'T00:00:00');
    const status = today >= expDate ? 'expired' : 'pro';
    return json({ valid: true, status, expiry, email: obj.e }, cors);
  } catch (e) {
    return json({ valid: false, status: 'invalid', reason: 'decode', detail: String(e && e.message || e) }, cors);
  }
}

function json(obj, headers, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

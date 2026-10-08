#!/usr/bin/env node
/**
 * FocusIn License Key 簽發工具（測試用）
 *
 * 用法：
 *   node tools/gen-license-key.js <email> <expiry:YYYY-MM-01> [--init]
 *   --init   首次初始化：生成 Ed25519 金鑰對（tools/license-keys/）
 *   無參數    顯示公鑰（供 App 內嵌）與用法
 *
 * Key 格式：FI-PRO-<b64url(payloadJSON)>.<b64url(ed25519簽名)>
 * payload: {"e":"email","p":"pro","x":"YYYY-MM-01"}
 * 到期模型：expiry 恒為某月 1 號；App 發現今天 >= expiry 即自動停用 Pro。
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DIR = path.join(__dirname, 'license-keys');
const PRIV = path.join(DIR, 'private.pem');
const PUB = path.join(DIR, 'public.pem');

function b64url(buf) { return Buffer.from(buf).toString('base64url'); }

function initKeys() {
  fs.mkdirSync(DIR, { recursive: true });
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  fs.writeFileSync(PRIV, privateKey.export({ type: 'pkcs8', format: 'pem' }));
  fs.writeFileSync(PUB, publicKey.export({ type: 'spki', format: 'pem' }));
  console.log('✓ 金鑰對已生成：');
  console.log('  私鑰:', PRIV);
  console.log('  公鑰:', PUB);
  printPubRaw(publicKey);
}

function printPubRaw(publicKey) {
  const der = publicKey.export({ type: 'spki', format: 'der' });
  // SPKI 結構：30 2a 30 05 06 03 2b 65 70 03 21 00 <32-byte raw key>
  const raw = der.subarray(der.length - 32);
  console.log('\nApp 內嵌公鑰（raw 32B base64）:');
  console.log(raw.toString('base64'));
}

function sign(email, expiry) {
  if (!fs.existsSync(PRIV)) { console.error('✗ 尚未初始化金鑰對，先執行 --init'); process.exit(1); }
  if (!/^\d{4}-\d{2}-01$/.test(expiry)) { console.error('✗ expiry 必須是 YYYY-MM-01 格式'); process.exit(1); }
  const payload = JSON.stringify({ e: email, p: 'pro', x: expiry });
  const priv = crypto.createPrivateKey(fs.readFileSync(PRIV));
  const sig = crypto.sign(null, Buffer.from(payload), priv);
  const key = `FI-PRO-${b64url(payload)}.${b64url(sig)}`;
  console.log('✓ License Key 已簽發：');
  console.log(key);
  console.log('\npayload:', payload);
  console.log('到期日:', expiry, '（App 當天 >= 此日期即自動停用 Pro）');
  // 同時印出公鑰供對照
  const pub = crypto.createPublicKey(fs.readFileSync(PUB));
  printPubRaw(pub);
}

const args = process.argv.slice(2);
if (args.includes('--init')) initKeys();
else if (args.length >= 2) sign(args[0], args[1]);
else {
  console.log('FocusIn License Key 簽發工具\n');
  console.log('  node tools/gen-license-key.js --init                  # 首次：生成金鑰對');
  console.log('  node tools/gen-license-key.js you@mail.com 2026-11-01 # 簽發 Key（expiry 為每月 1 號）\n');
  if (fs.existsSync(PUB)) printPubRaw(crypto.createPublicKey(fs.readFileSync(PUB)));
}

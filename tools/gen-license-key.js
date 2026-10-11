#!/usr/bin/env node
/**
 * FocusIn License Key 簽發工具
 *
 * 用法：
 *   node tools/gen-license-key.js --init                          # 首次：生成金鑰對（tools/license-keys/）
 *   node tools/gen-license-key.js you@mail.com --months 3         # 簽發 Key：到期 = 下個月起 N 個月後的 1 號
 *   node tools/gen-license-key.js you@mail.com 2026-11-01         # 簽發 Key：指定到期日（YYYY-MM-01）
 *   node tools/gen-license-key.js --batch users.csv --months 1    # 批次：每行一個 email，輸出 keys.csv
 *   node tools/gen-license-key.js --batch users.csv --out keys.csv --months 2
 *   node tools/gen-license-key.js                                 # 顯示公鑰與用法
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
  console.log('\n⚠️  此私鑰只存在本機；若需 Web 端自動簽發，把 seed 放進 Cloudflare Worker 的 Secret（勿放前端）。');
}

function printPubRaw(publicKey) {
  const der = publicKey.export({ type: 'spki', format: 'der' });
  // SPKI：30 2a 30 05 06 03 2b 65 70 03 21 00 <32-byte raw>
  const raw = der.subarray(der.length - 32);
  console.log('\nApp 內嵌公鑰（raw 32B base64）:');
  console.log(raw.toString('base64'));
}

/** 計算到期日：N 個月後的 1 號（若今天已是某月 N 日，仍算「下一個月起的 N 個月後」） */
function expiryAfterMonths(months) {
  const d = new Date();
  d.setDate(1);
  d.setMonth(d.getMonth() + months);
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-01';
}

function sign(email, expiry) {
  if (!fs.existsSync(PRIV)) { console.error('✗ 尚未初始化金鑰對，先執行 --init'); process.exit(1); }
  if (!/^\d{4}-\d{2}-01$/.test(expiry)) { console.error('✗ expiry 必須是 YYYY-MM-01 格式'); process.exit(1); }
  const payload = JSON.stringify({ e: email, p: 'pro', x: expiry });
  const priv = crypto.createPrivateKey(fs.readFileSync(PRIV));
  const sig = crypto.sign(null, Buffer.from(payload), priv);
  return `FI-PRO-${b64url(payload)}.${b64url(sig)}`;
}

/** 批次：users.csv（每行一個 email，可含表頭 email）→ keys.csv */
function batch(usersFile, outFile, months, fixedExpiry) {
  if (!fs.existsSync(PRIV)) { console.error('✗ 尚未初始化金鑰對，先執行 --init'); process.exit(1); }
  const lines = fs.readFileSync(usersFile, 'utf8').split(/\r?\n/)
    .map(l => l.trim()).filter(l => l && !l.startsWith('#'));
  if (lines.length === 0) { console.error('✗ users.csv 沒有內容'); process.exit(1); }
  const emails = lines.filter(l => l.includes('@'))
    .map(l => l.split(/[,;\t ]/)[0].trim());
  if (emails.length === 0) { console.error('✗ 找不到有效 email'); process.exit(1); }

  const rows = [];
  for (const email of emails) {
    const expiry = fixedExpiry || expiryAfterMonths(months);
    rows.push([email, expiry, sign(email, expiry)]);
  }
  const csv = 'email,expiry,license_key\n' +
    rows.map(r => r.join(',')).join('\n') + '\n';
  fs.writeFileSync(outFile, csv);
  console.log(`✓ 已簽發 ${rows.length} 個 Key → ${outFile}`);
  console.log(`  到期：${rows[0][1]}（每月 1 號繳費制；App 當天 >= 此日期自動停用）`);
  console.log('\n— 預覽（前 3 個）—');
  rows.slice(0, 3).forEach(r => console.log(`${r[0]}  ${r[2]}`));
}

const args = process.argv.slice(2);
if (args.includes('--init')) {
  initKeys();
} else if (args.includes('--batch')) {
  const users = args[args.indexOf('--batch') + 1];
  const monthsIdx = args.indexOf('--months');
  const months = monthsIdx >= 0 ? parseInt(args[monthsIdx + 1], 10) : 1;
  const outIdx = args.indexOf('--out');
  const out = outIdx >= 0 ? args[outIdx + 1] : path.join(__dirname, 'license-keys', 'keys.csv');
  if (!users) { console.error('✗ --batch 需要 users.csv 路徑'); process.exit(1); }
  batch(users, out, months, null);
} else {
  const email = args.find(a => a.includes('@'));
  const monthsIdx = args.indexOf('--months');
  const months = monthsIdx >= 0 ? parseInt(args[monthsIdx + 1], 10) : 1;
  const dateIdx = args.findIndex(a => /^\d{4}-\d{2}-01$/.test(a));
  const expiry = dateIdx >= 0 ? args[dateIdx] : expiryAfterMonths(months);
  if (email) {
    const key = sign(email, expiry);
    console.log('✓ License Key 已簽發：');
    console.log(key);
    console.log('\npayload:', JSON.stringify({ e: email, p: 'pro', x: expiry }));
    console.log('到期日:', expiry, '（App 當天 >= 此日期即自動停用 Pro）');
    if (fs.existsSync(PUB)) printPubRaw(crypto.createPublicKey(fs.readFileSync(PUB)));
  } else {
    console.log('FocusIn License Key 簽發工具\n');
    console.log('  node tools/gen-license-key.js --init');
    console.log('  node tools/gen-license-key.js you@mail.com --months 3');
    console.log('  node tools/gen-license-key.js you@mail.com 2026-11-01');
    console.log('  node tools/gen-license-key.js --batch users.csv --months 1 --out keys.csv\n');
    if (fs.existsSync(PUB)) printPubRaw(crypto.createPublicKey(fs.readFileSync(PUB)));
  }
}

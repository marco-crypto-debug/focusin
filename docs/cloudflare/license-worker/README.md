# FocusIn License Worker（Cloudflare Workers）

官網／App 的 License Key 安全簽發後端。**私鑰只存在 Worker Secret，永不進前端。**

## 部署（3 步）

```bash
# 1. 進入本目錄
cd docs/cloudflare/license-worker

# 2. 登入（如未登入）
npx wrangler login

# 3. 設定 Secrets（用 tools/gen-license-key.js 產生的同一把金鑰對）
npx wrangler secret put LICENSE_SEED    # ← 貼上私鑰 seed（raw 32B base64）
npx wrangler secret put LICENSE_PUB     # ← 貼上公鑰 raw base64
npx wrangler secret put ADMIN_KEY       # ← 自訂管理密碼（官網發 key 用）

# 4. 部署
npx wrangler deploy
```

部署完成會給你 `https://focusin-license.<你的subdomain>.workers.dev`。

## 如何取得 LICENSE_SEED

本機已有同一把金鑰對（`tools/license-keys/`）。seed 是 PKCS8 DER 的最後 32 bytes：

```bash
node -e "
const fs=require('fs');
const der=fs.readFileSync('tools/license-keys/private.pem');
const k=require('crypto').createPrivateKey(der);
console.log(k.export({type:'pkcs8',format:'der'}).subarray(-32).toString('base64'));
"
```

或重新生成一把（會使舊 Key 全部失效）：

```bash
node tools/gen-license-key.js --init
# 然後把輸出的 raw 公鑰貼進 App LicenseManager.pubKeyB64
```

## API

| 方法 | 路徑 | 用途 | 認證 |
|---|---|---|---|
| POST | `/api/license/gen` | body `{email, months}` → `{key, expiry, email}` | header `x-admin-key: <ADMIN_KEY>` |
| GET | `/api/license/verify?key=...` | 驗簽 + 到期狀態 → `{valid, status, expiry, email}` | 無 |
| GET | `/api/license/pub` | 回傳公鑰（供前端 verify） | 無 |

## 官網接入

官網 `docs/site/FocusIn官網.html` 的 license-box 會 POST 到
`LICENSE_WORKER_URL`（頁面開頭常數）。部署後把 workers.dev 網址填進去即可，
無需改其他代碼。

## 與 Dodo Payments 的關係（未來）

Dodo 付款成功後，由 Dodo Webhook 觸發本 Worker 的 `gen`（內部用 ADMIN_KEY），
自動簽發訂閱月份 Key 並寄出。現階段先用手動發 key（本 Worker + 官網區塊）。

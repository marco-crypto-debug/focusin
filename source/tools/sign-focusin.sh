#!/bin/bash
# ============================================================
# FocusIn — 自動簽名工具（免費自簽方案）
#
# 適用：沒有付費 Apple Developer Program（無法做正式公證）時，
#       用自簽證書給 App 簽名，配合 install-cert.sh 在學生機信任，
#       即可讓 Gatekeeper 放行、不再被識別為病毒。
#
# 用法（在 Marco 的構建機上）：
#   bash tools/sign-focusin.sh [app路徑...]
#   不給參數 = 自動簽名 release/staging-rel 下所有 .app
#
# 效果：
#   - 首次執行自動創建 10 年有效的 FocusIn 簽名證書（只會做一次）
#   - 簽名全部 App（Signature 從 adhoc 變成 FocusIn Signing）
#   - 導出公鑰 tools/focusin-signing.cer（學生機信任用）
# ============================================================

set -e

CERT_NAME="FocusIn Signing (Marco TSK)"
CERT_SUBJECT="/CN=FocusIn Signing (Marco TSK)/O=Marco TSK/C=HK"
CERT_DAYS=3650
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CER_OUT="$SCRIPT_DIR/focusin-signing.cer"
STAGING="/Users/marco/Documents/FocusIn/release/staging-rel"

echo ""
echo "FocusIn 自動簽名"
echo "================"

# ---------- 1. 證書不存在時自動創建（只做一次） ----------
if security find-identity -v -p codesigning 2>/dev/null | grep -q "FocusIn Signing"; then
  echo "✓ 證書已存在：$CERT_NAME"
else
  echo "創建簽名證書（${CERT_DAYS} 天有效）..."
  openssl req -x509 -newkey rsa:2048 \
    -keyout /tmp/focusin-key.pem -out /tmp/focusin-cert.pem \
    -days "$CERT_DAYS" -nodes -subj "$CERT_SUBJECT" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "keyUsage=digitalSignature" 2>/dev/null
  security import /tmp/focusin-cert.pem -k "$LOGIN_KEYCHAIN"
  security import /tmp/focusin-key.pem -k "$LOGIN_KEYCHAIN"
  security add-trusted-cert -d -r trustRoot -k "$LOGIN_KEYCHAIN" /tmp/focusin-cert.pem
  echo "✓ 證書已創建並導入鑰匙圈"
fi

# ---------- 2. 導出公鑰（給學生機信任用） ----------
security find-certificate -c "FocusIn Signing" -p "$LOGIN_KEYCHAIN" > "$CER_OUT"
echo "✓ 公鑰已導出：$CER_OUT"

# ---------- 3. 簽名 ----------
APPS=("$@")
if [ ${#APPS[@]} -eq 0 ]; then
  APPS=( "$STAGING"/*.app )
fi

for app in "${APPS[@]}"; do
  [ -d "$app" ] || { echo "⚠ 找不到：$app"; continue; }
  echo "→ 簽名：$app"
  codesign --force --sign "$CERT_NAME" "$app"
  codesign -dv "$app" 2>&1 | grep -E "Signature|Identifier" | sed 's/^/   /'
done

echo ""
echo "✅ 簽名完成。"
echo "把 $CER_OUT 連同 install-cert.sh 一起發到學生機，"
echo "每台執行一次：bash install-cert.sh"
echo ""

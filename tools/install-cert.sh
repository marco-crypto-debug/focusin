#!/bin/bash
# ============================================================
# FocusIn — 學生機信任腳本（每台 Mac 執行一次）
#
# 在教師端完成簽名後，把本腳本 + focusin-signing.cer
# 發到每一台學生機，執行一次即可讓 FocusIn 不再被攔截。
#
# 用法：在學生機終端機執行
#   bash install-cert.sh
# 會要求輸入管理員密碼（一次）。
# ============================================================

set -u

CERT="$(cd "$(dirname "$0")" && pwd)/focusin-signing.cer"
SYSTEM_KEYCHAIN="/Library/Keychains/System.keychain"

echo ""
echo "FocusIn 信任安裝"
echo "================"

# ---------- 1. 安裝證書到系統鑰匙圈 ----------
if [ ! -f "$CERT" ]; then
  echo "✗ 找不到 focusin-signing.cer（請確認它和本腳本在同一資料夾）"
  exit 1
fi

if security find-certificate -c "FocusIn Signing" "$SYSTEM_KEYCHAIN" >/dev/null 2>&1; then
  echo "✓ 證書已安裝"
else
  echo "安裝 FocusIn 證書（需要管理員密碼）..."
  sudo security add-trusted-cert -d -r trustRoot -k "$SYSTEM_KEYCHAIN" "$CERT"
  echo "✓ 證書已安裝並信任"
fi

# ---------- 2. 移除 quarantine + 加入白名單 ----------
FIXED=0
for app in \
  "/Applications/FocusIn Teacher.app" \
  "/Applications/FocusIn Student.app" \
  "/Applications/FocusIn Alpha Teacher.app" \
  "/Applications/FocusIn Alpha Student.app" \
  "$HOME/Applications/FocusIn Teacher.app" \
  "$HOME/Applications/FocusIn Student.app"; do

  if [ -d "$app" ]; then
    echo "→ 處理：$app"
    xattr -dr com.apple.quarantine "$app" 2>/dev/null
    sudo spctl --add --label "FocusIn" "$app" 2>/dev/null
    echo "   ✓ 已放行"
    FIXED=1
  fi
done

echo ""
if [ "$FIXED" = "1" ]; then
  echo "✅ 完成！FocusIn 現在可以正常打開，不會再被攔截。"
else
  echo "⚠ 沒找到已安裝的 FocusIn App，請先把它們拖入「應用程式」資料夾後再跑一次。"
fi
echo ""

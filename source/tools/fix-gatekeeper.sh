#!/bin/bash
# ============================================================
# FocusIn — Gatekeeper 一鍵修復工具（免費方案）
#
# 問題：FocusIn 目前是 ad-hoc 簽名、未經 Apple 公證，
#       macOS 會攔截並顯示「無法驗證開發者 / 已損壞」。
#
# 用法：在每一台被攔截的 Mac 上，打開「終端機」執行：
#       bash ~/Downloads/fix-gatekeeper.sh
# 需要管理員密碼（輸入一次）。
# ============================================================

set -u

echo ""
echo "FocusIn Gatekeeper 一鍵修復"
echo "============================"
echo ""

FIXED=0
for app in \
  "/Applications/FocusIn Teacher.app" \
  "/Applications/FocusIn Student.app" \
  "/Applications/FocusIn Alpha Teacher.app" \
  "/Applications/FocusIn Alpha Student.app" \
  "$HOME/Applications/FocusIn Teacher.app" \
  "$HOME/Applications/FocusIn Student.app"; do

  if [ -d "$app" ]; then
    echo "→ 處理中：$app"

    # 1) 移除 quarantine 攔截標記（最重要的一步，不需管理員）
    xattr -dr com.apple.quarantine "$app" 2>/dev/null
    echo "   ✓ 已移除 quarantine 標記"

    # 2) 加入 Gatekeeper 白名單（需要管理員密碼）
    if sudo spctl --add --label "FocusIn" "$app" 2>/dev/null; then
      echo "   ✓ 已加入 Gatekeeper 白名單"
    else
      echo "   ⚠ 加入白名單需要管理員權限（可跳過，通常上一步已足夠）"
    fi

    FIXED=1
  fi
done

echo ""
if [ "$FIXED" = "1" ]; then
  echo "✅ 完成！現在可以正常雙擊打開 FocusIn 了。"
else
  echo "⚠ 找不到已安裝的 FocusIn App。"
  echo "  請先把 FocusIn 拖入「應用程式」資料夾，再重新執行本腳本。"
fi
echo ""
echo "如果仍被攔截：右鍵點 App → 選「開啟」→ 再按一次「開啟」即可。"
echo ""

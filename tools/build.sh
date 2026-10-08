#!/bin/bash
# ============================================================
# FocusIn 一鍵構建：stable / alpha / beta 三版 × 教師端/學生端
#
# 用法：
#   bash tools/build.sh            # 預設構建 beta（含 Pro License）
#   bash tools/build.sh stable     # 構建穩定版（僅畫面 + 退出保護）
#   bash tools/build.sh alpha      # 構建 Alpha（聲音 + Pro License）
#   bash tools/build.sh all        # 三版全建
#
# 產物：
#   release/staging-<版>/*.app     （已簽名）
#   release/<版>/FocusIn-*.dmg     （可分發）
# ============================================================
set -e

ROOT="/Users/marco/Documents/FocusIn"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macos14.0"
BUILD_SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
VERSION_BASE="1.4.1"

SHARED_SRC=(
  "$ROOT/Shared/Networking/PeerConnection.swift"
  "$ROOT/Shared/Networking/PeerDiscovery.swift"
  "$ROOT/Shared/Networking/PeerTransport.swift"
  "$ROOT/Shared/Protocol/CommandMessage.swift"
  "$ROOT/Shared/Protocol/CommandType.swift"
  "$ROOT/Shared/Utility/DiagLog.swift"
  "$ROOT/Shared/Utility/LicenseManager.swift"
  "$ROOT/Shared/Utility/LoginStartManager.swift"
  "$ROOT/Shared/Utility/MenuBarManager.swift"
  "$ROOT/Shared/Utility/FocusInAppState.swift"
  "$ROOT/Shared/Utility/FocusInTheme.swift"
  "$ROOT/Shared/Utility/QuitGuard.swift"
  "$ROOT/Shared/Utility/UpdateChecker.swift"
)
TEACHER_SRC=(
  "$ROOT/TeacherApp/TeacherApp.swift"
  "$ROOT/TeacherApp/TeacherViewModel.swift"
  "$ROOT/TeacherApp/ScreenBroadcaster.swift"
  "$ROOT/TeacherApp/Views/DeviceListView.swift"
)
STUDENT_SRC=(
  "$ROOT/StudentApp/StudentApp.swift"
  "$ROOT/StudentApp/CommandListener.swift"
  "$ROOT/StudentApp/AudioPlayer.swift"
  "$ROOT/StudentApp/FileWipeManager.swift"
  "$ROOT/StudentApp/Kiosk/InputInterceptor.swift"
  "$ROOT/StudentApp/Kiosk/KioskConfig.swift"
  "$ROOT/StudentApp/Kiosk/KioskLockView.swift"
  "$ROOT/StudentApp/Kiosk/KioskModeController.swift"
  "$ROOT/StudentApp/Views/StatusView.swift"
)

build_variant() {
  local VARIANT="$1"       # stable | alpha | beta
  local MACRO=""           # -D 參數
  local SUFFIX=""          # 顯示名與 bundle id 後綴
  local STAGE="$ROOT/release/staging-rel"
  local OUTDIR="$ROOT/release/stable"
  local DMG_TAG=""
  local CAP="Stable"       # 顯示用大寫首字母

  case "$VARIANT" in
    stable) MACRO="-D FOCUSIN_STABLE";  SUFFIX="";      CAP="Stable"; STAGE="$ROOT/release/staging-rel";  OUTDIR="$ROOT/release/stable"; DMG_TAG="";;
    alpha)  MACRO="-D FOCUSIN_ALPHA";   SUFFIX=".alpha"; CAP="Alpha"; STAGE="$ROOT/release/staging-alpha"; OUTDIR="$ROOT/release/alpha"; DMG_TAG="Alpha-";;
    beta)   MACRO="-D FOCUSIN_BETA";    SUFFIX=".beta";  CAP="Beta"; STAGE="$ROOT/release/staging-beta"; OUTDIR="$ROOT/release/beta"; DMG_TAG="Beta-";;
    *) echo "✗ 未知版本：$VARIANT（stable/alpha/beta/all）"; exit 1;;
  esac

  local VERSION="$VERSION_BASE"
  # 版本標記用「-」尾綴（如 1.4.0-beta），bundle id 後綴用「.」（如 com.classroom.teacher.beta）
  local TAG_SUFFIX=""
  case "$VARIANT" in
    alpha) TAG_SUFFIX="-alpha";;
    beta)  TAG_SUFFIX="-beta";;
  esac
  [ -n "$TAG_SUFFIX" ] && VERSION="$VERSION_BASE$TAG_SUFFIX"

  echo ""
  echo "=============================================="
  echo "構建 $VARIANT 版（v$VERSION / $BUILD_SHA）"
  echo "=============================================="

  mkdir -p "$STAGE" "$OUTDIR"

  build_app() {
    local APP="$1"          # TeacherApp | StudentApp
    local EXE="$2"          # exe 名稱
    local BUNDLE_ID="$3"    # 完整 bundle id
    local DISPLAY="$4"      # 顯示名
    local SRC=("${SHARED_SRC[@]}")

    if [ "$APP" = "TeacherApp" ]; then
      SRC+=("${TEACHER_SRC[@]}")
    else
      SRC+=("${STUDENT_SRC[@]}")
    fi

    local APPDIR="$STAGE/$APP.app"
    rm -rf "$APPDIR"
    mkdir -p "$APPDIR/Contents/MacOS"

    echo "→ $APP（$DISPLAY / $BUNDLE_ID）"
    swiftc -sdk "$SDK" -parse-as-library -O -target "$TARGET" \
      $MACRO \
      -o "$APPDIR/Contents/MacOS/$EXE" \
      "${SRC[@]}"

    # Info.plist
    local PLIST_SRC="$ROOT/$APP/Info.plist"
    local PLIST="$APPDIR/Contents/Info.plist"
    cp "$PLIST_SRC" "$PLIST"
    plutil -replace CFBundleExecutable -string "$EXE" "$PLIST"
    plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
    plutil -replace CFBundleName -string "$DISPLAY" "$PLIST"
    plutil -replace CFBundleDisplayName -string "$DISPLAY" "$PLIST"
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
    plutil -replace CFBundleVersion -string "$BUILD_SHA" "$PLIST"
    plutil -replace CFBundlePackageType -string "APPL" "$PLIST"
  }

  # 教師端
  build_app "TeacherApp" \
    "TeacherApp$CAP" \
    "com.classroom.teacher$SUFFIX" \
    "FocusIn $CAP 教師端"

  # 學生端
  build_app "StudentApp" \
    "StudentApp$CAP" \
    "com.classroom.student$SUFFIX" \
    "FocusIn $CAP 學生端"

  # 簽名
  echo "→ 簽名..."
  bash "$ROOT/tools/sign-focusin.sh" "$STAGE"/*.app

  # DMG
  make_dmg() {
    local APP="$1" NAME="$2"
    local DMG="$OUTDIR/$NAME.dmg"
    local TMP="$STAGE/$NAME"
    rm -rf "$TMP"; mkdir -p "$TMP"
    cp -R "$STAGE/$APP.app" "$TMP/"
    # 附帶信任工具
    cp "$ROOT/tools/install-cert.sh" "$TMP/" 2>/dev/null || true
    cp "$ROOT/tools/focusin-signing.cer" "$TMP/" 2>/dev/null || true
    hdiutil create -volname "$NAME" -srcfolder "$TMP" -ov -format UDZO "$DMG" >/dev/null
    echo "→ DMG：$DMG"
  }

  make_dmg "TeacherApp" "FocusIn-$DMG_TAG""Teacher"
  make_dmg "StudentApp" "FocusIn-$DMG_TAG""Student"

  echo "✓ $VARIANT 版完成"
}

case "${1:-beta}" in
  all)
    build_variant stable
    build_variant alpha
    build_variant beta
    ;;
  *) build_variant "${1:-beta}" ;;
esac

echo ""
echo "全部完成 ✅"

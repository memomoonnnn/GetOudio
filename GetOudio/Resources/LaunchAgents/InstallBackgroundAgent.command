#!/usr/bin/env bash
set -euo pipefail

LABEL="com.shengjiacheng.GetOudio.agent"
PLIST_NAME="$LABEL.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_APP_PATH="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_PATH="$DEFAULT_APP_PATH"
USER_ID="$(id -u)"
TARGET_DIR="$HOME/Library/LaunchAgents"
TARGET_PLIST="$TARGET_DIR/$PLIST_NAME"

if [[ "${1:-}" == "--app" ]]; then
  APP_PATH="${2:?missing app path}"
fi

if [[ "${1:-}" == "--uninstall" ]]; then
  /bin/launchctl bootout "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || true
  /bin/rm -f "$TARGET_PLIST"
  echo "已移除 Get Oudio 后台活动。"
  exit 0
fi

if [[ "$APP_PATH" != /Applications/*.app ]]; then
  echo "请先将 Get Oudio.app 拖入 Applications 文件夹，再从应用设置中安装后台活动。" >&2
  exit 1
fi

EXECUTABLE="$APP_PATH/Contents/MacOS/Get Oudio"
TEMPLATE="$APP_PATH/Contents/Resources/LaunchAgents/$PLIST_NAME"
[[ -x "$EXECUTABLE" ]] || { echo "找不到 Get Oudio 可执行文件：$EXECUTABLE" >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "找不到后台活动模板：$TEMPLATE" >&2; exit 1; }

/bin/mkdir -p "$TARGET_DIR"
TEMP_PLIST="$(mktemp "${TMPDIR:-/tmp}/GetOudioLaunchAgent.XXXXXX")"
trap '/bin/rm -f "$TEMP_PLIST"' EXIT
/bin/cp "$TEMPLATE" "$TEMP_PLIST"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $EXECUTABLE" "$TEMP_PLIST"
/usr/bin/plutil -lint "$TEMP_PLIST" >/dev/null

/bin/launchctl bootout "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || true
/bin/mv "$TEMP_PLIST" "$TARGET_PLIST"
trap - EXIT
/bin/launchctl bootstrap "gui/$USER_ID" "$TARGET_PLIST"
/bin/launchctl kickstart -k "gui/$USER_ID/$LABEL"
/bin/launchctl print "gui/$USER_ID/$LABEL" >/dev/null

echo "Get Oudio 后台活动已安装并启动。可以关闭此 Terminal 窗口。"

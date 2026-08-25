#!/usr/bin/env bash
set -euo pipefail

LABEL="com.shengjiacheng.GetOudio.agent"
PLIST_NAME="$LABEL.plist"
RUNTIME_LABEL="com.shengjiacheng.GetOudio.runtime-worker"
RUNTIME_PLIST_NAME="$RUNTIME_LABEL.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_APP_PATH="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_PATH="$DEFAULT_APP_PATH"
USER_ID="$(id -u)"
TARGET_DIR="$HOME/Library/LaunchAgents"
TARGET_PLIST="$TARGET_DIR/$PLIST_NAME"
RUNTIME_TARGET_PLIST="$TARGET_DIR/$RUNTIME_PLIST_NAME"
LEGACY_ROOT="$HOME/Library/Application Support/GetOudioV2"
CONTROL_ROOT="$HOME/Library/Containers/com.shengjiacheng.GetOudio/Data/Library/Application Support/GetOudioV2"

if [[ "${1:-}" == "--app" ]]; then
  APP_PATH="${2:?missing app path}"
fi

if [[ "${1:-}" == "--uninstall" ]]; then
  /bin/launchctl bootout "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || true
  /bin/launchctl bootout "gui/$USER_ID/$RUNTIME_LABEL" >/dev/null 2>&1 || true
  /bin/rm -f "$TARGET_PLIST"
  /bin/rm -f "$RUNTIME_TARGET_PLIST"
  echo "已移除 Get Oudio 后台服务；保留 Runtime 和下载数据。"
  exit 0
fi

if [[ "$APP_PATH" != /Applications/*.app ]]; then
  echo "请先将 Get Oudio.app 拖入 Applications 文件夹，再从应用设置中安装后台活动。" >&2
  exit 1
fi

EXECUTABLE="$APP_PATH/Contents/MacOS/Get Oudio"
RUNTIME_WORKER="$APP_PATH/Contents/Helpers/GetOudioAMRuntimeWorker.app/Contents/MacOS/GetOudioAMRuntimeWorker"
TEMPLATE="$APP_PATH/Contents/Resources/LaunchAgents/$PLIST_NAME"
RUNTIME_TEMPLATE="$APP_PATH/Contents/Resources/LaunchAgents/$RUNTIME_PLIST_NAME"
[[ -x "$EXECUTABLE" ]] || { echo "找不到 Get Oudio 可执行文件：$EXECUTABLE" >&2; exit 1; }
[[ -x "$RUNTIME_WORKER" ]] || { echo "找不到 Apple Music Runtime Worker：$RUNTIME_WORKER" >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "找不到后台活动模板：$TEMPLATE" >&2; exit 1; }
[[ -f "$RUNTIME_TEMPLATE" ]] || { echo "找不到 Runtime Worker 模板：$RUNTIME_TEMPLATE" >&2; exit 1; }

/bin/mkdir -p "$TARGET_DIR"
TEMP_PLIST="$(mktemp "${TMPDIR:-/tmp}/GetOudioLaunchAgent.XXXXXX")"
RUNTIME_TEMP_PLIST="$(mktemp "${TMPDIR:-/tmp}/GetOudioRuntimeWorker.XXXXXX")"
trap '/bin/rm -f "$TEMP_PLIST" "$RUNTIME_TEMP_PLIST"' EXIT
/bin/cp "$TEMPLATE" "$TEMP_PLIST"
/bin/cp "$RUNTIME_TEMPLATE" "$RUNTIME_TEMP_PLIST"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $EXECUTABLE" "$TEMP_PLIST"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $RUNTIME_WORKER" "$RUNTIME_TEMP_PLIST"
/usr/bin/plutil -lint "$TEMP_PLIST" >/dev/null
/usr/bin/plutil -lint "$RUNTIME_TEMP_PLIST" >/dev/null

/bin/launchctl bootout "gui/$USER_ID/$LABEL" >/dev/null 2>&1 || true
/bin/launchctl bootout "gui/$USER_ID/$RUNTIME_LABEL" >/dev/null 2>&1 || true

MIGRATION_MARKER="$CONTROL_ROOT/.control-migration-complete"
if [[ ! -f "$MIGRATION_MARKER" ]]; then
  /bin/mkdir -p "$CONTROL_ROOT"
  for relative_path in \
    "queued-jobs.json" \
    "share-events.json" \
    "pending-apple-music-downloads.json" \
    "notification-events" \
    "conversion-log.txt" \
    "RecordingControl" \
    "Library/Caches/Recordings"; do
    source_path="$LEGACY_ROOT/$relative_path"
    destination_path="$CONTROL_ROOT/$relative_path"
    if [[ -e "$source_path" && ! -e "$destination_path" ]]; then
      /bin/mkdir -p "$(/usr/bin/dirname "$destination_path")"
      /usr/bin/ditto "$source_path" "$destination_path"
    fi
  done
  /usr/bin/touch "$MIGRATION_MARKER"
fi

/bin/mv "$TEMP_PLIST" "$TARGET_PLIST"
/bin/mv "$RUNTIME_TEMP_PLIST" "$RUNTIME_TARGET_PLIST"
trap - EXIT
/bin/launchctl bootstrap "gui/$USER_ID" "$TARGET_PLIST"
/bin/launchctl bootstrap "gui/$USER_ID" "$RUNTIME_TARGET_PLIST"
/bin/launchctl kickstart -k "gui/$USER_ID/$LABEL"
/bin/launchctl print "gui/$USER_ID/$LABEL" >/dev/null
/bin/launchctl print "gui/$USER_ID/$RUNTIME_LABEL" >/dev/null

echo "Get Oudio 后台活动和按需 Apple Music Runtime Worker 已安装。可以关闭此 Terminal 窗口。"

#!/bin/zsh
# Validate a staged bundle, then replace the installation with rollback on failure.
set -euo pipefail
ROOT="${0:A:h:h}"
"$ROOT/scripts/build-app.sh"
INSTALL_DIR="${TANGLER_INSTALL_DIR:-/Applications}"
mkdir -p "$INSTALL_DIR"
INSTALL_DIR="${INSTALL_DIR:A}"
TARGET="$INSTALL_DIR/Tangler.app"
LOCK="$INSTALL_DIR/.Tangler-install.lock"
if ! mkdir "$LOCK"; then
  print -u2 "另一个安装正在进行，或上次中断留下了锁：$LOCK"
  exit 1
fi

TRANSACTION=""
BACKUP=""
COMMITTED=0
PUBLISHING=0
finish_install() {
  local result=$? keep_transaction=0
  trap - EXIT HUP INT TERM
  if [[ -n "$TRANSACTION" ]]; then
    if (( ! COMMITTED )); then
      if [[ -e "$BACKUP" || -L "$BACKUP" ]]; then
        if [[ ! -e "$TARGET" && ! -L "$TARGET" ]] || mv "$TARGET" "$TRANSACTION/failed.app"; then
          if mv "$BACKUP" "$TARGET"; then
            print -u2 "安装未完成，已恢复旧版：$TARGET"
          else
            keep_transaction=1
          fi
        else
          keep_transaction=1
        fi
      elif (( PUBLISHING )) && [[ -e "$TARGET" || -L "$TARGET" ]]; then
        mv "$TARGET" "$TRANSACTION/failed.app" || keep_transaction=1
      fi
    fi
    if (( keep_transaction )); then
      print -u2 "自动恢复失败，安装文件和旧版备份保留在：$TRANSACTION"
      result=1
    else
      rm -rf -- "$TRANSACTION" || result=1
    fi
  fi
  rmdir "$LOCK" || result=1
  return $result
}
trap finish_install EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Staging and backup are on the destination volume, so publication is a rename.
TRANSACTION=$(mktemp -d "$INSTALL_DIR/.Tangler-install.XXXXXX")
STAGED="$TRANSACTION/Tangler.app"
BACKUP="$TRANSACTION/previous.app"
ditto "$ROOT/build/Tangler.app" "$STAGED"
plutil -lint "$STAGED/Contents/Info.plist"
[[ -x "$STAGED/Contents/MacOS/Tangler" ]]
codesign --verify --deep --strict "$STAGED"

is_target_process() {
  local executable
  executable=$(ps -p "$1" -o comm= 2>/dev/null) || return 1
  [[ "${executable:A}" == "$TARGET/Contents/MacOS/Tangler" ]]
}

# Only stop this installation; developer builds and other installed copies stay running.
for pid in ${(f)"$(pgrep -x Tangler || true)"}; do
  is_target_process "$pid" || continue
  kill -TERM "$pid" 2>/dev/null || true
  for attempt in {1..50}; do
    is_target_process "$pid" || break
    sleep 0.1
  done
  if is_target_process "$pid"; then
    print -u2 "目标 Tangler 未在 5 秒内退出，强制结束进程 $pid。"
    kill -KILL "$pid" 2>/dev/null || true
    for attempt in {1..20}; do
      is_target_process "$pid" || break
      sleep 0.1
    done
    if is_target_process "$pid"; then
      print -u2 "无法退出目标进程，保留当前安装。"
      exit 1
    fi
  fi
done

if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  mv "$TARGET" "$BACKUP"
fi
PUBLISHING=1
mv "$STAGED" "$TARGET"
open "$TARGET"
COMMITTED=1
print "已安装并打开 $TARGET"

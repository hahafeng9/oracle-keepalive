#!/bin/bash
# Oracle Always Free 实例保活（本机负载版）
#
# 安全声明（请先通读全文再跑）：
#  - 不调用任何 OCI / Oracle API，不需要、不读取、不发送 OCI 密钥、租户 ID、私钥。
#  - 不读取 ~/.oci、~/.ssh、/etc/shadow、环境变量里的任何密钥。
#  - 除你自己配的 TG Bot 外，不向任何第三方发数据；不配 TG 就完全不联网。
#  - 只做一件事：本机定时跑一段单核 CPU 负载，让 CPU 第 95 百分位超过 20%。
#
# 原理：
#  Oracle 闲置判定是 7 天内 CPU、网络、内存三项同时低于 20%（CPU 为 P95）。
#  三项必须同时成立才算闲置，所以只要 CPU 一项破 20% 就不算闲置。
#  本脚本每 3 小时跑 15 分钟单核负载，约占时间 8.3%（>5%），足以把 P95 CPU 推过 20%。
#  负载用 nice -n 19 低优先级跑：你的程序优先抢 CPU，负载只吃空闲 CPU，
#  日常用起来几乎感觉不到；系统总 CPU 利用率照样计入 nice 进程，所以保活效果不变。
#  不主动占内存，避免小内存机器 OOM；CPU 单项已足够。
#
# TG 通知（可选，默认不刷屏）：
#  配置文件 /opt/oracle-keepalive/tg.conf（600 权限，只存本机，绝不进 Git 仓库）：
#    TG_BOT_TOKEN="123456:xxxx"
#    TG_CHAT_ID="123456789"
#    NOTIFY_EVERY_RUN=0   # 0=每天首次运行后发 1 条汇总，失败立即发；1=每轮都发
#  通知时机：安装时 1 条、每天首次负载完成 1 条、失败立即 1 条，其余运行只写本地日志。
#  每条 TG 通知都带机器信息（主机名 + 公网 IP + 内网 IP），多台机发来时一眼能分清是哪台。
#
# 日志：/var/log/oracle-keepalive.log
# 状态：/var/lib/oracle-keepalive/last-notify-date
# 定时：cron 每 3 小时整点运行一次，由 install.sh 安装

INSTALL_DIR="/opt/oracle-keepalive"
LOG_FILE="/var/log/oracle-keepalive.log"
STATE_DIR="/var/lib/oracle-keepalive"
CONFIG_FILE="$INSTALL_DIR/tg.conf"
HOST="$(hostname 2>/dev/null || echo unknown)"
LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "$LOCAL_IP" ] && LOCAL_IP="unknown"
MACHINE_INFO="机器：${HOST} | 内网 IP：${LOCAL_IP}"
LOAD_SECONDS=900
NOTIFY_EVERY_RUN=0
TG_BOT_TOKEN=""
TG_CHAT_ID=""

log() {
  echo "$(date '+%F %T') [$HOST] $*" | tee -a "$LOG_FILE"
}

send_tg() {
  # 只在配了 Token 和 Chat ID 时发；Token 绝不写日志
  [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ] || return 0
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=$1" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
}

mkdir -p "$STATE_DIR" 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/oracle-keepalive.log"

# 读 TG 配置（不存在就跳过通知，不报错）
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE" 2>/dev/null || true
fi
# 只有配了 TG 才探公网 IP（不配 TG 就完全不联网）；探不到用内网 IP 兜底
if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
  EXT_IP="$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")"
  [ -z "$EXT_IP" ] && EXT_IP="$LOCAL_IP"
  MACHINE_INFO="机器：${HOST} | 公网 IP：${EXT_IP} | 内网 IP：${LOCAL_IP}"
fi

# 防重叠：上一轮还没跑完就跳过（flock 不可用时用 PID 文件兜底）
LOCK_FILE="/tmp/oracle-keepalive.lock"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  flock -n 9 || { log "上一轮还在跑，跳过本轮"; exit 0; }
fi

START="$(date +%s)"
log "保活负载开始（${LOAD_SECONDS} 秒，单核）"

RC=0
if command -v stress-ng >/dev/null 2>&1; then
  nice -n 19 stress-ng --cpu 1 --timeout "${LOAD_SECONDS}s" >/dev/null 2>&1 || RC=$?
else
  # yes 只占 1 个核，nice -n 19 低优先级；timeout 到时返回 124，属正常结束，不是失败
  nice -n 19 timeout "$LOAD_SECONDS" yes >/dev/null 2>&1 || RC=$?
  [ "$RC" = "124" ] && RC=0
fi

END="$(date +%s)"
USED=$((END - START))
LOADAVG="$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo unknown)"

if [ "$RC" != "0" ]; then
  log "保活负载失败，退出码 $RC"
  send_tg "⚠️ Oracle 保活失败
${MACHINE_INFO}
负载退出码 $RC，时间 $(date '+%F %T')，请登录该机检查。"
  exit 1
fi

log "保活负载完成，用时 ${USED} 秒，负载 $LOADAVG"

# TG：每天首次完成发 1 条；NOTIFY_EVERY_RUN=1 时每轮都发；失败上面已立即发
TODAY="$(date '+%F')"
LAST_FILE="$STATE_DIR/last-notify-date"
LAST="$(cat "$LAST_FILE" 2>/dev/null || echo "")"
if [ "$NOTIFY_EVERY_RUN" = "1" ] || [ "$LAST" != "$TODAY" ]; then
  send_tg "✅ Oracle 保活
${MACHINE_INFO}
今日负载已完成 1 轮（${LOAD_SECONDS} 秒单核），时间 $(date '+%F %T')，负载 $LOADAVG。"
  echo "$TODAY" > "$LAST_FILE" 2>/dev/null || true
fi

exit 0

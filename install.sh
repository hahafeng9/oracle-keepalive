#!/bin/bash
# Oracle 保活一键安装（请先在 GitHub 上通读 keepalive.sh 再跑）
# 用法（每台 Oracle 机上各跑一次，root 或 sudo）：
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/hahafeng9/oracle-keepalive/main/install.sh)"
# 或先下载审阅再跑（推荐第一次）：
#   curl -fsSL -o install.sh https://raw.githubusercontent.com/hahafeng9/oracle-keepalive/main/install.sh
#   cat install.sh
#   sudo bash install.sh
# TG 通知可选：安装时交互输入 Token/Chat ID，或提前设置环境变量
#   sudo TG_BOT_TOKEN="123:xxx" TG_CHAT_ID="123456" bash install.sh
set -e
REPO_RAW="https://raw.githubusercontent.com/hahafeng9/oracle-keepalive/main"
INSTALL_DIR="/opt/oracle-keepalive"
SCRIPT="$INSTALL_DIR/keepalive.sh"

if [ "$(id -u)" != "0" ]; then
  echo "请用 root 或 sudo 运行：sudo bash install.sh"
  exit 1
fi

echo "== Oracle 保活安装 =="
mkdir -p "$INSTALL_DIR"
echo "下载 keepalive.sh ..."
curl -fsSL -o "$SCRIPT" "$REPO_RAW/keepalive.sh"
chmod +x "$SCRIPT"

# ---- TG 配置（Token 只存本机 tg.conf，600 权限，绝不上传 GitHub）----
TG_TOKEN="${TG_BOT_TOKEN:-}"
TG_CHAT="${TG_CHAT_ID:-}"
if [ -z "$TG_TOKEN" ] && [ -t 0 ]; then
  read -r -p "TG Bot Token（回车跳过 = 不发 TG 通知）: " TG_TOKEN || true
fi
if [ -z "$TG_CHAT" ] && [ -t 0 ] && [ -n "$TG_TOKEN" ]; then
  read -r -p "TG Chat ID（回车跳过 = 不发 TG 通知）: " TG_CHAT || true
fi
if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT" ]; then
  printf 'TG_BOT_TOKEN="%s"\nTG_CHAT_ID="%s"\nNOTIFY_EVERY_RUN=0\n' "$TG_TOKEN" "$TG_CHAT" > "$INSTALL_DIR/tg.conf"
  chmod 600 "$INSTALL_DIR/tg.conf"
  echo "TG 配置已写 $INSTALL_DIR/tg.conf（600）"
else
  echo "未配 TG：跳过通知。之后想加可手动建 $INSTALL_DIR/tg.conf（见 README）。"
fi

# ---- cron：每 3 小时整点跑一次，已存在则不重复加 ----
CRON_LINE="0 */3 * * * $SCRIPT"
if crontab -l 2>/dev/null | grep -Fq "$SCRIPT"; then
  echo "cron 已存在，跳过添加"
else
  (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
  echo "cron 已添加：$CRON_LINE"
fi

# ---- 10 秒冒烟测试（不是完整 15 分钟负载，只验证脚本能跑）----
echo "冒烟测试（10 秒，低优先级）..."
nice -n 19 timeout 10 yes >/dev/null 2>&1 || true
touch /var/log/oracle-keepalive.log 2>/dev/null || true
echo "$(date '+%F %T') [$(hostname)] 保活安装完成，冒烟测试通过" >> /var/log/oracle-keepalive.log

# 安装成功 TG 通知（带机器信息，多台机发来时能分清）
if [ -f "$INSTALL_DIR/tg.conf" ]; then
  # shellcheck disable=SC1091
  . "$INSTALL_DIR/tg.conf"
  _HOST="$(hostname 2>/dev/null || echo unknown)"
  _LOCAL="$(hostname -I 2>/dev/null | awk '{print $1}')"
  _EXT="$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "$_LOCAL")"
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=✅ Oracle 保活已安装
机器：${_HOST} | 公网 IP：${_EXT} | 内网 IP：${_LOCAL}
每 3 小时跑 15 分钟单核负载，TG 通知为每天首次完成 1 条、失败立即发。" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || echo "TG 安装通知发送失败（不影响保活本身）"
fi

echo "== 安装完成 =="
echo "脚本：$SCRIPT"
echo "日志：/var/log/oracle-keepalive.log"
echo "验证：crontab -l ；tail /var/log/oracle-keepalive.log"
echo "卸载：见仓库 uninstall.sh"

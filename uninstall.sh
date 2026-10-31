#!/bin/bash
# Oracle 保活卸载（root 或 sudo）
set -e
if [ "$(id -u)" != "0" ]; then
  echo "请用 root 或 sudo 运行"
  exit 1
fi
crontab -l 2>/dev/null | grep -v -F "/opt/oracle-keepalive/keepalive.sh" | crontab - || true
rm -rf /opt/oracle-keepalive /var/lib/oracle-keepalive /tmp/oracle-keepalive.lock
echo "已卸载：cron 已删，/opt/oracle-keepalive 已删（日志 /var/log/oracle-keepalive.log 未删，如需删请手动 rm）"

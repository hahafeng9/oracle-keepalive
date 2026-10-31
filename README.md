# Oracle Always Free 保活脚本（本机负载版）

## 三台都要装吗？要

闲置判定是**按单台实例**算的：每台的 CPU、网络、内存是分开统计的。
一台跑负载，抬的是它自己的 CPU，帮不了另外两台。
所以三台 Oracle 机上，每台各跑一次一键安装。
账号 30 天登录是另一层（整个账号），那个只要偶尔登录一次控制台就行，和每台装脚本不冲突。

## 这个脚本做什么、不做什么

做：
- 每 3 小时整点，跑 15 分钟单核 CPU 负载（约占时间 8.3%，足以把 CPU 第 95 百分位推过 20%）
- 写本地日志 `/var/log/oracle-keepalive.log`
- 配了 TG 才发通知：安装成功 1 条、每天首次负载完成 1 条、失败立即 1 条，其余运行静默不刷屏；每条通知都带机器信息（主机名 + 公网 IP + 内网 IP），三台机发来时能分清是哪台

不做（请先通读 `keepalive.sh` 全文验证）：
- 不调用 OCI / Oracle API，不需要、不读取、不发送 OCI 密钥、租户 ID、私钥
- 不读取 `~/.oci`、`~/.ssh`、`/etc/shadow`、环境变量里的密钥
- 除你自己配的 TG Bot 外，不向任何第三方发数据
- 不主动占内存，避免小内存机器 OOM；CPU 单项破 20% 已足够破闲置条件

## 一键安装（每台各跑一次）

先审阅再跑（推荐第一次）：

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/hahafeng9/oracle-keepalive/main/install.sh
cat install.sh
sudo bash install.sh
```

或直接一键：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/hahafeng9/oracle-keepalive/main/install.sh)"
```

安装时会问 TG Bot Token 和 Chat ID，回车跳过就是不发 TG 通知。
也可以提前用环境变量：

```bash
sudo TG_BOT_TOKEN="123:xxx" TG_CHAT_ID="123456" bash install.sh
```

## TG 通知怎么配 / 怎么改

Token 只存本机 `/opt/oracle-keepalive/tg.conf`（600 权限），**绝不要把 Token 写进仓库、Issue 或聊天公开处**。

之后想补配或改配置：

```bash
sudo tee /opt/oracle-keepalive/tg.conf > /dev/null <<'EOF'
TG_BOT_TOKEN="你的Token"
TG_CHAT_ID="你的Chat ID"
NOTIFY_EVERY_RUN=0
EOF
sudo chmod 600 /opt/oracle-keepalive/tg.conf
```

- `NOTIFY_EVERY_RUN=0`（默认）：每天首次完成 1 条、失败立即发
- `NOTIFY_EVERY_RUN=1`：每 3 小时一轮都发（3 台就是每天 24 条，比较吵，不推荐）

Chat ID 获取：先私聊你的 Bot 发 `/start`，再用 Bot API 的 `getUpdates` 看，或用你已知的私聊 ID。

## 验证

```bash
crontab -l
tail -f /var/log/oracle-keepalive.log
```

安装只做 10 秒冒烟测试，不会立刻跑满 15 分钟；下一个 3 小时整点会自动跑第一轮，日志里出现“保活负载完成”即正常。

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/hahafeng9/oracle-keepalive/main/uninstall.sh -o uninstall.sh
sudo bash uninstall.sh
```

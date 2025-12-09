#!/bin/bash
# WireGuard网络修复脚本

echo "修复WireGuard网络连接..."

# 停止WireGuard
wg-quick down wg0

# 获取网络接口
INTERFACE="ens18"  # 从你的路由表看到是ens18

# 清理旧规则
iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null
iptables -D FORWARD -o wg0 -j ACCEPT 2>/dev/null
iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE 2>/dev/null

# 添加必要的iptables规则
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE

# 修改wg0.conf配置
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = cH828l4DDdGkAuKL7oN4PuKMfLX46VCOyT8e41xI/3w=
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens18 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens18 -j MASQUERADE

[Peer]
PublicKey = 6WTcB6vhCo3lGK4+lCPB+YBMFuA5exG65SzIBchX1ws=
AllowedIPs = 10.8.0.2/32
EOF

# 启动WireGuard
wg-quick up wg0

echo "修复完成！请测试手机连接。"
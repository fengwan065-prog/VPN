#!/bin/bash
# WireGuard VPN一键安装脚本（RockyLinux专用）
# 作者：凝神无忧
# 日期：2025年12月10日

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   WireGuard VPN 一键安装脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 配置变量
SERVER_IP="154.36.184.228"  # 你的服务器IP
WG_PORT="51820"             # WireGuard监听端口
WG_NETWORK="10.8.0.0/24"    # 内网网段
WG_SERVER_IP="10.8.0.1"     # 服务器内网IP
WG_CLIENT_IP="10.8.0.2"     # 第一个客户端内网IP

echo -e "${YELLOW}[1/10] 更新系统包管理器...${NC}"
dnf update -y

echo -e "${YELLOW}[2/10] 安装必要软件包...${NC}"
dnf install -y wireguard-tools qrencode firewalld

echo -e "${YELLOW}[3/10] 创建WireGuard配置目录...${NC}"
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard
cd /etc/wireguard

echo -e "${YELLOW}[4/10] 生成服务器密钥对...${NC}"
wg genkey | tee server-private.key | wg pubkey > server-public.key
chmod 600 server-private.key server-public.key

echo -e "${YELLOW}[5/10] 生成客户端密钥对...${NC}"
wg genkey | tee client-private.key | wg pubkey > client-public.key
chmod 600 client-private.key client-public.key

echo -e "${YELLOW}[6/10] 创建服务器配置文件...${NC}"
cat > wg0.conf <<EOF
[Interface]
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = $(cat server-private.key)
PostUp = firewall-cmd --zone=public --add-port ${WG_PORT}/udp && firewall-cmd --zone=public --add-masquerade
PostDown = firewall-cmd --zone=public --remove-port ${WG_PORT}/udp && firewall-cmd --zone=public --remove-masquerade
SaveConfig = true

[Peer]
PublicKey = $(cat client-public.key)
AllowedIPs = ${WG_CLIENT_IP}/32
EOF

echo -e "${YELLOW}[7/10] 配置防火墙...${NC}"
systemctl start firewalld
systemctl enable firewalld
firewall-cmd --permanent --add-port=${WG_PORT}/udp
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload

echo -e "${YELLOW}[8/10] 创建客户端配置文件...${NC}"
cat > /root/wg-client.conf <<EOF
[Interface]
PrivateKey = $(cat client-private.key)
Address = ${WG_CLIENT_IP}/24
DNS = 8.8.8.8, 1.1.1.1
MTU = 1420

[Peer]
PublicKey = $(cat server-public.key)
Endpoint = ${SERVER_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

echo -e "${YELLOW}[9/10] 配置网络转发...${NC}"
if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
fi
sysctl -p

echo -e "${YELLOW}[10/10] 启动WireGuard服务...${NC}"
wg-quick down wg0 2>/dev/null
wg-quick up wg0
systemctl enable wg-quick@wg0

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   WireGuard VPN 安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}📊 服务器信息：${NC}"
echo "  公网IP: ${SERVER_IP}"
echo "  端口: ${WG_PORT}"
echo "  内网网段: ${WG_NETWORK}"
echo "  服务器内网IP: ${WG_SERVER_IP}"
echo ""
echo -e "${YELLOW}📁 客户端配置文件：${NC}"
echo "  位置: /root/wg-client.conf"
echo ""
echo -e "${YELLOW}🔧 管理命令：${NC}"
echo "  查看状态: sudo wg show"
echo "  重启服务: sudo systemctl restart wg-quick@wg0"
echo "  查看日志: sudo journalctl -u wg-quick@wg0 -f"
echo ""
echo -e "${YELLOW}📱 客户端连接：${NC}"
echo "  1. 查看配置文件: cat /root/wg-client.conf"
echo "  2. 生成二维码: qrencode -t ansiutf8 < /root/wg-client.conf"
echo ""
echo -e "${GREEN}========================================${NC}"
#!/bin/bash
# WireGuard VPN一键安装脚本
# 版本: 2.0
# GitHub: https://github.com/fengwan065-prog/wireguard-vpn-setup

set -e  # 遇到错误退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 配置变量（用户可以修改）
SERVER_IP="YOUR_SERVER_IP"          # 自动检测或手动设置
WG_PORT="51820"                     # WireGuard端口
WG_NETWORK="10.8.0.0/24"            # VPN内网网段
WG_SERVER_IP="10.8.0.1"             # 服务器内网IP
DNS_SERVERS="8.8.8.8,1.1.1.1"       # DNS服务器

# 显示横幅
show_banner() {
    clear
    echo -e "${GREEN}"
    echo "================================================="
    echo "   WireGuard VPN 一键安装脚本"
    echo "   版本: 2.0 | RockyLinux/CentOS 专用"
    echo "   GitHub: https://github.com/fengwan065-prog/wireguard-vpn-setup"
    echo "================================================="
    echo -e "${NC}"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本需要root权限运行！${NC}"
        echo -e "请使用: ${YELLOW}sudo bash $0${NC}"
        exit 1
    fi
}

# 检测系统
detect_system() {
    if [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release)
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
    else
        OS=$(uname -s)
    fi
    
    echo -e "${BLUE}[信息] 操作系统: $OS${NC}"
    
    # 检测包管理器
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    else
        echo -e "${RED}错误: 不支持的包管理器${NC}"
        exit 1
    fi
}

# 自动获取服务器IP
get_server_ip() {
    echo -e "${BLUE}[信息] 正在获取服务器公网IP...${NC}"
    
    # 尝试多个IP检测服务
    local ip_services=(
        "ifconfig.me"
        "ipinfo.io/ip"
        "api.ipify.org"
        "icanhazip.com"
    )
    
    for service in "${ip_services[@]}"; do
        SERVER_IP=$(curl -s --connect-timeout 3 $service 2>/dev/null)
        if [[ $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${GREEN}[成功] 获取到公网IP: $SERVER_IP${NC}"
            return 0
        fi
    done
    
    echo -e "${YELLOW}[警告] 无法自动获取公网IP${NC}"
    read -p "请输入服务器公网IP地址: " SERVER_IP
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}[1/10] 安装必要软件包...${NC}"
    
    $PKG_MANAGER update -y
    
    # 安装WireGuard工具
    if ! command -v wg &> /dev/null; then
        $PKG_MANAGER install -y wireguard-tools
    fi
    
    # 安装其他必要工具
    $PKG_MANAGER install -y curl qrencode
    
    # 安装防火墙（如果未安装）
    if ! command -v firewall-cmd &> /dev/null; then
        $PKG_MANAGER install -y firewalld
        systemctl start firewalld
        systemctl enable firewalld
    fi
}

# 配置目录和密钥
setup_wireguard() {
    echo -e "${YELLOW}[2/10] 配置WireGuard目录...${NC}"
    
    # 备份旧配置
    if [ -d "/etc/wireguard" ]; then
        BACKUP_DIR="/etc/wireguard.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${BLUE}[信息] 备份旧配置到: $BACKUP_DIR${NC}"
        cp -r /etc/wireguard "$BACKUP_DIR"
    fi
    
    # 创建配置目录
    mkdir -p /etc/wireguard
    chmod 700 /etc/wireguard
    cd /etc/wireguard
    
    echo -e "${YELLOW}[3/10] 生成密钥对...${NC}"
    
    # 生成服务器密钥
    umask 077
    wg genkey | tee server-private.key | wg pubkey > server-public.key
    SERVER_PRIVATE_KEY=$(cat server-private.key)
    SERVER_PUBLIC_KEY=$(cat server-public.key)
    
    # 生成第一个客户端密钥
    wg genkey | tee client1-private.key | wg pubkey > client1-public.key
    CLIENT_PRIVATE_KEY=$(cat client1-private.key)
    CLIENT_PUBLIC_KEY=$(cat client1-public.key)
    
    echo -e "${GREEN}[成功] 密钥生成完成${NC}"
}

# 创建服务器配置
create_server_config() {
    echo -e "${YELLOW}[4/10] 创建服务器配置文件...${NC}"
    
    cat > wg0.conf <<EOF
[Interface]
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
PostUp = firewall-cmd --zone=public --add-port ${WG_PORT}/udp && firewall-cmd --zone=public --add-masquerade
PostDown = firewall-cmd --zone=public --remove-port ${WG_PORT}/udp && firewall-cmd --zone=public --remove-masquerade
SaveConfig = true

[Peer]
# Client 1
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = 10.8.0.2/32
EOF
    
    echo -e "${GREEN}[成功] 服务器配置创建完成${NC}"
}

# 配置防火墙
setup_firewall() {
    echo -e "${YELLOW}[5/10] 配置防火墙...${NC}"
    
    # 确保firewalld运行
    systemctl start firewalld 2>/dev/null || true
    
    # 添加端口规则
    firewall-cmd --permanent --add-port=${WG_PORT}/udp
    firewall-cmd --permanent --add-masquerade
    firewall-cmd --reload
    
    echo -e "${GREEN}[成功] 防火墙配置完成${NC}"
}

# 创建客户端配置
create_client_config() {
    echo -e "${YELLOW}[6/10] 创建客户端配置文件...${NC}"
    
    CLIENT_CONFIG_DIR="/root/wireguard-clients"
    mkdir -p "$CLIENT_CONFIG_DIR"
    
    # 客户端1配置
    cat > "${CLIENT_CONFIG_DIR}/client1.conf" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = 10.8.0.2/24
DNS = ${DNS_SERVERS}
MTU = 1420

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    
    # 创建统一链接
    ln -sf "${CLIENT_CONFIG_DIR}/client1.conf" "/root/wg-client.conf"
    
    echo -e "${GREEN}[成功] 客户端配置创建完成${NC}"
}

# 配置网络
setup_networking() {
    echo -e "${YELLOW}[7/10] 配置网络转发...${NC}"
    
    # 启用IP转发
    if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    fi
    
    # 应用配置
    sysctl -p
    
    echo -e "${GREEN}[成功] 网络转发配置完成${NC}"
}

# 启动服务
start_service() {
    echo -e "${YELLOW}[8/10] 启动WireGuard服务...${NC}"
    
    # 停止可能存在的旧服务
    wg-quick down wg0 2>/dev/null || true
    
    # 启动新服务
    wg-quick up wg0
    
    # 设置开机自启
    systemctl enable wg-quick@wg0
    
    echo -e "${GREEN}[成功] WireGuard服务启动完成${NC}"
}

# 验证安装
verify_installation() {
    echo -e "${YELLOW}[9/10] 验证安装...${NC}"
    
    echo -e "${BLUE}1. 检查WireGuard状态:${NC}"
    wg show || echo -e "${RED}[错误] WireGuard未运行${NC}"
    
    echo -e "${BLUE}2. 检查端口监听:${NC}"
    ss -lunp | grep ${WG_PORT} || echo -e "${YELLOW}[警告] 端口未监听${NC}"
    
    echo -e "${BLUE}3. 检查服务状态:${NC}"
    systemctl status wg-quick@wg0 --no-pager -l | head -10
    
    echo -e "${GREEN}[成功] 验证完成${NC}"
}

# 显示安装结果
show_result() {
    echo -e "${GREEN}"
    echo "================================================="
    echo "   WireGuard VPN 安装完成！"
    echo "================================================="
    echo -e "${NC}"
    
    echo -e "${YELLOW}📊 服务器信息:${NC}"
    echo "  公网IP: ${SERVER_IP}"
    echo "  端口: ${WG_PORT}"
    echo "  内网网段: ${WG_NETWORK}"
    echo "  服务器内网IP: ${WG_SERVER_IP}"
    echo ""
    
    echo -e "${YELLOW}📁 配置文件位置:${NC}"
    echo "  服务器配置: /etc/wireguard/wg0.conf"
    echo "  客户端配置: /root/wireguard-clients/client1.conf"
    echo "  快捷链接: /root/wg-client.conf"
    echo ""
    
    echo -e "${YELLOW}🔧 管理命令:${NC}"
    echo "  查看状态: sudo wg show"
    echo "  重启服务: sudo systemctl restart wg-quick@wg0"
    echo "  停止服务: sudo wg-quick down wg0"
    echo "  启动服务: sudo wg-quick up wg0"
    echo ""
    
    echo -e "${YELLOW}📱 客户端连接:${NC}"
    echo "  1. 查看配置文件: cat /root/wg-client.conf"
    echo "  2. 生成二维码: qrencode -t ansiutf8 < /root/wg-client.conf"
    echo ""
    
    echo -e "${GREEN}🎉 恭喜！WireGuard VPN 已成功安装！${NC}"
    echo ""
}

# 添加客户端功能
add_client_menu() {
    echo -e "${BLUE}是否要添加更多客户端？${NC}"
    read -p "输入 'y' 添加新客户端，或按回车跳过: " choice
    
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        add_new_client
    fi
}

# 添加新客户端
add_new_client() {
    read -p "请输入新客户端名称: " client_name
    
    # 清理客户端名
    client_name=$(echo "$client_name" | tr -cd '[:alnum:]_-')
    
    if [ -z "$client_name" ]; then
        echo -e "${RED}[错误] 客户端名不能为空${NC}"
        return
    fi
    
    cd /etc/wireguard
    
    # 生成客户端密钥
    wg genkey | tee ${client_name}-private.key | wg pubkey > ${client_name}-public.key
    
    # 查找可用的IP地址
    for i in {3..254}; do
        if ! grep -q "10.8.0.$i/32" wg0.conf; then
            client_ip="10.8.0.$i"
            break
        fi
    done
    
    if [ -z "$client_ip" ]; then
        echo -e "${RED}[错误] 没有可用的IP地址${NC}"
        return
    fi
    
    # 添加到服务器配置
    echo "" >> wg0.conf
    echo "[Peer]" >> wg0.conf
    echo "# ${client_name}" >> wg0.conf
    echo "PublicKey = $(cat ${client_name}-public.key)" >> wg0.conf
    echo "AllowedIPs = ${client_ip}/32" >> wg0.conf
    
    # 创建客户端配置
    CLIENT_CONFIG_DIR="/root/wireguard-clients"
    cat > "${CLIENT_CONFIG_DIR}/${client_name}.conf" <<EOF
[Interface]
PrivateKey = $(cat ${client_name}-private.key)
Address = ${client_ip}/24
DNS = ${DNS_SERVERS}
MTU = 1420

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    
    # 重启WireGuard应用配置
    wg-quick down wg0
    wg-quick up wg0
    
    echo -e "${GREEN}[成功] 客户端 ${client_name} 添加完成！${NC}"
    echo "配置文件: ${CLIENT_CONFIG_DIR}/${client_name}.conf"
    echo "内网IP: ${client_ip}"
}

# 主函数
main() {
    show_banner
    check_root
    detect_system
    get_server_ip
    install_dependencies
    setup_wireguard
    create_server_config
    setup_firewall
    create_client_config
    setup_networking
    start_service
    verify_installation
    show_result
    add_client_menu
}

# 运行主函数
main "$@"

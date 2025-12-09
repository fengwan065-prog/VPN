#!/bin/bash
# WireGuard VPN管理脚本
# 版本: 1.0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONFIG_DIR="/etc/wireguard"
CLIENT_DIR="/root/wireguard-clients"

show_menu() {
    clear
    echo -e "${GREEN}"
    echo "=========================================="
    echo "      WireGuard VPN 管理脚本"
    echo "=========================================="
    echo -e "${NC}"
    echo "1. 添加新客户端"
    echo "2. 列出所有客户端"
    echo "3. 删除客户端"
    echo "4. 显示客户端配置"
    echo "5. 生成二维码"
    echo "6. 重启WireGuard服务"
    echo "7. 查看服务状态"
    echo "8. 备份配置"
    echo "9. 恢复配置"
    echo "0. 退出"
    echo ""
}

add_client() {
    echo -e "${YELLOW}添加新客户端${NC}"
    read -p "请输入客户端名称: " client_name
    
    # 清理名称
    client_name=$(echo "$client_name" | tr -cd '[:alnum:]_-')
    
    if [ -z "$client_name" ]; then
        echo -e "${RED}错误: 名称不能为空${NC}"
        return
    fi
    
    if [ -f "${CLIENT_DIR}/${client_name}.conf" ]; then
        echo -e "${RED}错误: 客户端已存在${NC}"
        return
    fi
    
    cd $CONFIG_DIR
    
    # 生成密钥
    wg genkey | tee ${client_name}-private.key | wg pubkey > ${client_name}-public.key
    
    # 查找可用IP
    for i in {2..254}; do
        if ! grep -q "10.8.0.$i/32" wg0.conf; then
            client_ip="10.8.0.$i"
            break
        fi
    done
    
    if [ -z "$client_ip" ]; then
        echo -e "${RED}错误: 没有可用的IP地址${NC}"
        return
    fi
    
    # 添加到服务器配置
    echo "" >> wg0.conf
    echo "[Peer]" >> wg0.conf
    echo "# ${client_name}" >> wg0.conf
    echo "PublicKey = $(cat ${client_name}-public.key)" >> wg0.conf
    echo "AllowedIPs = ${client_ip}/32" >> wg0.conf
    
    # 创建客户端配置
    SERVER_PUBLIC_KEY=$(cat server-public.key)
    SERVER_IP=$(grep "Endpoint" ${CLIENT_DIR}/client1.conf 2>/dev/null | cut -d'=' -f2 | cut -d':' -f1)
    PORT=$(grep "ListenPort" wg0.conf | cut -d'=' -f2 | tr -d ' ')
    
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")
    fi
    
    if [ -z "$PORT" ]; then
        PORT="51820"
    fi
    
    cat > "${CLIENT_DIR}/${client_name}.conf" <<EOF
[Interface]
PrivateKey = $(cat ${client_name}-private.key)
Address = ${client_ip}/24
DNS = 8.8.8.8,1.1.1.1
MTU = 1420

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_IP}:${PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    
    # 重启服务
    wg-quick down wg0
    wg-quick up wg0
    
    echo -e "${GREEN}客户端 ${client_name} 添加成功！${NC}"
    echo "配置文件: ${CLIENT_DIR}/${client_name}.conf"
    echo "内网IP: ${client_ip}"
    read -p "按回车键继续..."
}

list_clients() {
    echo -e "${YELLOW}客户端列表:${NC}"
    echo ""
    
    if [ ! -d "$CLIENT_DIR" ]; then
        echo "无客户端配置目录"
        return
    fi
    
    for client_file in ${CLIENT_DIR}/*.conf; do
        if [ -f "$client_file" ]; then
            client_name=$(basename "$client_file" .conf)
            client_ip=$(grep "Address" "$client_file" | cut -d'=' -f2 | tr -d ' ' | cut -d'/' -f1)
            echo "名称: $client_name | IP: $client_ip"
        fi
    done
    
    echo ""
    echo "服务器状态:"
    wg show
    read -p "按回车键继续..."
}

# ... 其他管理功能 ...

main() {
    while true; do
        show_menu
        read -p "请选择操作 (0-9): " choice
        
        case $choice in
            1) add_client ;;
            2) list_clients ;;
            3) echo "删除客户端功能" ;;
            4) echo "显示配置功能" ;;
            5) echo "生成二维码功能" ;;
            6) systemctl restart wg-quick@wg0 ;;
            7) systemctl status wg-quick@wg0 ;;
            8) echo "备份功能" ;;
            9) echo "恢复功能" ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
    done
}

# 运行
main
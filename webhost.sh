#!/data/data/com.termux/files/usr/bin/env bash
# ============================================
# WebHost tool
# Author: Alienkrishn [Anon4You]
# Description: Serve local directory and expose via tunnel
# ============================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Global variables
SERVER_PID=""
TUNNEL_PID=""
TEMP_DIR="${TMPDIR:-/tmp}/webserver_$$"
LOG_FILE="$TEMP_DIR/server.log"
TUNNEL_LOG="$TEMP_DIR/tunnel.log"
WEB_PATH=""
PORT=""
SERVER_TYPE=""
TUNNEL_TYPE=""

# Cleanup function
cleanup() {
    printf "\n${YELLOW}${BOLD}Cleaning up...${RESET}\n"
    
    if [[ -n "$SERVER_PID" ]] && kill -0 $SERVER_PID 2>/dev/null; then
        kill $SERVER_PID 2>/dev/null
        printf "${DIM}✓ Stopped server process${RESET}\n"
    fi
    
    if [[ -n "$TUNNEL_PID" ]] && kill -0 $TUNNEL_PID 2>/dev/null; then
        kill $TUNNEL_PID 2>/dev/null
        printf "${DIM}✓ Stopped tunnel process${RESET}\n"
    fi
    
    pkill -f "php -S" 2>/dev/null
    pkill -f "python3 -m http.server" 2>/dev/null
    pkill -f "http-server" 2>/dev/null
    pkill -f "ssh -R" 2>/dev/null
    pkill -f "tmole" 2>/dev/null
    pkill -f "cloudflared tunnel" 2>/dev/null
    pkill -f "ngrok" 2>/dev/null
    
    rm -rf "$TEMP_DIR" 2>/dev/null
    printf "${GREEN}✓ Cleanup complete${RESET}\n"
    exit 0
}

trap cleanup SIGINT SIGTERM SIGTSTP

check_internet() {
    printf "${CYAN}🔍 Checking internet connectivity...${RESET}\n"
    if curl -s --max-time 5 https://www.google.com >/dev/null 2>&1; then
        printf "${GREEN}✓ Internet connected${RESET}\n\n"
    else
        printf "${RED}${BOLD}✗ No internet connection! Please check your network.${RESET}\n"
        exit 1
    fi
}

check_port() {
    if lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null 2>&1; then
        printf "${RED}✗ Port $1 is already in use${RESET}\n"
        return 1
    fi
    return 0
}

# Banner using asciibanner with "Shadow" font
print_banner() {
    clear
    if command -v figlet >/dev/null 2>&1; then
        figlet -f slant "WebHost" 2>/dev/null
    else
        echo -e "${BOLD}${CYAN}=== WebHost ===${RESET}"
    fi
    echo -e "${GREEN}${BOLD}Author:${RESET} ${CYAN}Alienkrishn [Anon4You]${RESET}"
    echo -e "${GREEN}${BOLD}About:${RESET} ${CYAN}Easily serve any local Web${RESET}"
    echo -e "${CYAN}       To the internet using TunnelMole ${RESET}"
    echo -e "${CYAN}       Localhost.run, Cloudflared, or Ngrok.${RESET}"
    echo -e "${DIM}─────────────────────────────────────────────────${RESET}\n"
}
# Server implementations
start_php_server() {
    local port=$1
    local path=$2
    php -S 0.0.0.0:$port -t "$path" > "$LOG_FILE" 2>&1 &
    echo $!
}

start_python_server() {
    local port=$1
    local path=$2
    (
        cd "$path"
        python3 -m http.server $port
    ) > "$LOG_FILE" 2>&1 &
    echo $!
}

start_node_server() {
    local port=$1
    local path=$2
    http-server "$path" -p $port -a 0.0.0.0 > "$LOG_FILE" 2>&1 &
    echo $!
}

# Tunnel implementations
start_tunnelmole() {
    local port=$1
    tmole $port > "$TUNNEL_LOG" 2>&1 &
    echo $!
}

start_localhostrun() {
    local port=$1
    ssh -R 80:localhost:$port nokey@localhost.run > "$TUNNEL_LOG" 2>&1 &
    echo $!
}

start_cloudflared() {
    local port=$1
    cloudflared tunnel --url localhost:$port > "$TUNNEL_LOG" 2>&1 &
    echo $!
}

start_ngrok() {
    local port=$1
    ngrok http $port --log=stdout > "$TUNNEL_LOG" 2>&1 &
    echo $!
}

# Extract tunnel URL from log
extract_tunnel_url() {
    local type=$1
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        case $type in
            1) # TunnelMole
                url=$(grep -o 'https://[-0-9a-z]*\.tunnelmole.net' "$TUNNEL_LOG" 2>/dev/null | head -1)
                ;;
            2) # Localhost.run
                url=$(grep -o 'https://[-0-9a-z]*\.lhr\.life' "$TUNNEL_LOG" 2>/dev/null | head -1)
                ;;
            3) # Cloudflared
                url=$(grep -o 'https://[-0-9a-z]*\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | head -1)
                ;;
            4) # Ngrok - using local API first, fallback to log
                # Try to get URL from ngrok's API
                api_response=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null)
                if [[ -n "$api_response" ]]; then
                    # Extract first public URL (tunnels[0].public_url)
                    url=$(echo "$api_response" | grep -o '"public_url":"[^"]*"' | head -1 | cut -d'"' -f4)
                    # If it contains 'ngrok' (any domain, including .dev)
                    if [[ "$url" == *"ngrok"* ]]; then
                        echo "$url"
                        return 0
                    fi
                fi
                # Fallback: grep log for common ngrok domains (.io, .free.app, .dev)
                url=$(grep -Eo 'https://[-0-9a-z]*\.(ngrok\.io|ngrok-free\.app|ngrok\.dev)' "$TUNNEL_LOG" 2>/dev/null | head -1)
                ;;
        esac
        
        if [[ -n "$url" ]]; then
            echo "$url"
            return 0
        fi
        
        sleep 1
        ((attempt++))
    done
    
    return 1
}

# Main script
main() {
    print_banner
    check_internet
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Get web directory
    printf "${CYAN}📁 Target path : ${RESET}"
    read -r web
    WEB_PATH="${web:-.}"
    
    if [ ! -d "$WEB_PATH" ]; then
        printf "${RED}✗ Directory not found!${RESET}\n"
        exit 1
    fi
    printf "${GREEN}✓ Using directory: $WEB_PATH${RESET}\n\n"
    
    # Get port
    printf "${CYAN}🔌 Local port (default: 8080): ${RESET}"
    read -r port
    PORT="${port:-8080}"
    
    if ! check_port $PORT; then
        exit 1
    fi
    printf "${GREEN}✓ Port $PORT is available${RESET}\n\n"
    
    # Select server type
    echo -e "${BOLD}${MAGENTA}┌─────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}${MAGENTA}│         SELECT SERVER TYPE              │${RESET}"
    echo -e "${BOLD}${MAGENTA}└─────────────────────────────────────────┘${RESET}"
    echo -e "${GREEN}1) PHP Server (php -S)${RESET}"
    echo -e "${GREEN}2) Python Server (python3 -m http.server)${RESET}"
    echo -e "${GREEN}3) Node.js Server (http-server)${RESET}"
    printf "${CYAN}👉 Enter choice [1-3]: ${RESET}"
    read -r server_choice
    
    case $server_choice in
        1)
            if ! command -v php >/dev/null 2>&1; then
                printf "${RED}✗ PHP is not installed!${RESET}\n"
                exit 1
            fi
            printf "${YELLOW}🚀 Starting PHP server...${RESET}\n"
            SERVER_PID=$(start_php_server $PORT "$WEB_PATH")
            SERVER_TYPE="PHP"
            ;;
        2)
            if ! command -v python3 >/dev/null 2>&1; then
                printf "${RED}✗ Python3 is not installed!${RESET}\n"
                exit 1
            fi
            printf "${YELLOW}🐍 Starting Python server...${RESET}\n"
            SERVER_PID=$(start_python_server $PORT "$WEB_PATH")
            SERVER_TYPE="Python"
            ;;
        3)
            if ! command -v http-server >/dev/null 2>&1; then
                printf "${RED}✗ http-server is not installed! Install with: npm install -g http-server${RESET}\n"
                exit 1
            fi
            printf "${YELLOW}📦 Starting Node.js server (http-server)...${RESET}\n"
            SERVER_PID=$(start_node_server $PORT "$WEB_PATH")
            SERVER_TYPE="Node.js (http-server)"
            ;;
        *)
            printf "${RED}✗ Invalid choice!${RESET}\n"
            exit 1
            ;;
    esac
    
    sleep 2
    
    if kill -0 $SERVER_PID 2>/dev/null; then
        printf "${GREEN}✓ ${SERVER_TYPE} server started successfully on port $PORT${RESET}\n"
        printf "${DIM}  ➜ Local access: http://localhost:$PORT${RESET}\n\n"
    else
        printf "${RED}✗ Failed to start server!${RESET}\n"
        exit 1
    fi
    
    # Select tunnel service
    echo -e "${BOLD}${MAGENTA}┌─────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}${MAGENTA}│         SELECT TUNNEL SERVICE           │${RESET}"
    echo -e "${BOLD}${MAGENTA}└─────────────────────────────────────────┘${RESET}"
    echo -e "${GREEN}1) TunnelMole${RESET}"
    echo -e "${GREEN}2) Localhost.run${RESET}"
    echo -e "${GREEN}3) Cloudflared${RESET}"
    echo -e "${GREEN}4) Ngrok${RESET}"
    printf "${CYAN}👉 Enter choice [1-4]: ${RESET}"
    read -r tunnel_choice
    
    printf "${YELLOW}🔗 Starting tunnel...${RESET}\n"
    case $tunnel_choice in
        1)
            if ! command -v tmole >/dev/null 2>&1; then
                printf "${RED}✗ TunnelMole not installed! Install with: npm install -g tunnelmole${RESET}\n"
                cleanup
            fi
            TUNNEL_PID=$(start_tunnelmole $PORT)
            TUNNEL_TYPE="TunnelMole"
            ;;
        2)
            if ! command -v ssh >/dev/null 2>&1; then
                printf "${RED}✗ SSH client not found!${RESET}\n"
                cleanup
            fi
            TUNNEL_PID=$(start_localhostrun $PORT)
            TUNNEL_TYPE="Localhost.run"
            ;;
        3)
            if ! command -v cloudflared >/dev/null 2>&1; then
                printf "${RED}✗ Cloudflared not installed! Get it from: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation${RESET}\n"
                cleanup
            fi
            TUNNEL_PID=$(start_cloudflared $PORT)
            TUNNEL_TYPE="Cloudflared"
            ;;
        4)
            if ! command -v ngrok >/dev/null 2>&1; then
                printf "${RED}✗ Ngrok not installed! Download from: https://ngrok.com/download${RESET}\n"
                cleanup
            fi
            TUNNEL_PID=$(start_ngrok $PORT)
            TUNNEL_TYPE="Ngrok"
            ;;
        *)
            printf "${RED}✗ Invalid choice!${RESET}\n"
            cleanup
            ;;
    esac
    
    printf "${YELLOW}⏳ Waiting for tunnel to establish...${RESET}\n"
    TUNNEL_URL=$(extract_tunnel_url $tunnel_choice)
    
    if [ -n "$TUNNEL_URL" ]; then
        printf "\n${GREEN}${BOLD}══════════════════════════════════════════════════════════${RESET}\n"
        printf "${GREEN}✓ Tunnel established!${RESET}\n"
        printf "${CYAN}🌐 Public URL: ${BOLD}${YELLOW}$TUNNEL_URL${RESET}\n"
        printf "${CYAN}🔒 Local URL:  ${BOLD}http://localhost:$PORT${RESET}\n"
        printf "${CYAN}📁 Serving:    ${BOLD}$WEB_PATH${RESET}\n"
        printf "${CYAN}🚀 Server:     ${BOLD}${SERVER_TYPE}${RESET}\n"
        printf "${CYAN}🔧 Tunnel:     ${BOLD}${TUNNEL_TYPE}${RESET}\n"
        printf "${GREEN}${BOLD}══════════════════════════════════════════════════════════${RESET}\n\n"
        printf "${BLUE}💡 Share the Public URL with anyone to access your local server!${RESET}\n"
        printf "${YELLOW}⚠️  Press ${BOLD}ENTER${RESET}${YELLOW} to stop the server and exit...${RESET}\n"
        read -r
    else
        printf "${RED}✗ Failed to get tunnel URL after 30 seconds${RESET}\n"
        printf "${YELLOW}Check the log at: $TUNNEL_LOG${RESET}\n"
    fi
    
    cleanup
}

# Run main function
main

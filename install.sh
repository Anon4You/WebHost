#!/data/data/com.termux/files/usr/bin/env bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

echo -e "${GREEN}WebHost Installer${RESET}"
echo "==================="

if [ -z "$PREFIX" ]; then
    echo -e "${RED}Error: Not running in Termux${RESET}"
    exit 1
fi

VOID_LIST="$PREFIX/etc/apt/sources.list.d/termuxvoid.list"
if [ ! -f "$VOID_LIST" ]; then
    echo -e "${YELLOW}Installing termuxvoid repository...${RESET}"
    bash <(curl -sL https://is.gd/termuxvoid) -s
fi

packages=(python php ngrok cloudflared figlet openssh curl npm)

for pkg in "${packages[@]}"; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing $pkg...${RESET}"
        apt install -y "$pkg"
    else
        echo -e "${GREEN}✓ $pkg already installed${RESET}"
    fi
done

if ! command -v http-server >/dev/null 2>&1; then
    echo -e "${YELLOW}Installing http-server...${RESET}"
    npm install -g http-server
else
    echo -e "${GREEN}✓ http-server already installed${RESET}"
fi

if ! command -v tmole >/dev/null 2>&1; then
    echo -e "${YELLOW}Installing tunnelmole...${RESET}"
    npm install -g tunnelmole
else
    echo -e "${GREEN}✓ tmole already installed${RESET}"
fi

echo -e "${YELLOW}Installing webhost command...${RESET}"
curl -o "$PREFIX/bin/webhost" -sL "https://github.com/Anon4You/WebHost/raw/main/webhost.sh"
chmod +x "$PREFIX/bin/webhost"

if command -v webhost >/dev/null 2>&1; then
    echo -e "${GREEN}✓ webhost installed successfully${RESET}"
else
    echo -e "${RED}Warning: webhost command not found in PATH${RESET}"
    echo -e "${YELLOW}Manually install with:${RESET}"
    echo -e "curl -o $PREFIX/bin/webhost -sL https://github.com/Anon4You/WebHost/raw/main/webhost.sh && chmod +x $PREFIX/bin/webhost"
fi

echo -e "${GREEN}========================================${RESET}"
echo -e "${GREEN}Installation complete!${RESET}"
echo -e "Run: ${YELLOW}webhost${RESET}"

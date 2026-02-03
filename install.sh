#!/usr/bin/env bash
# ============================================================================
#  NFT Gift Bot — Installer
#
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/fitymico/nft-gift-bot-release/main/install.sh | sudo bash
#    wget -qO- https://raw.githubusercontent.com/fitymico/nft-gift-bot-release/main/install.sh | sudo bash
#
#  Скачивает бинарник, настраивает окружение, создаёт systemd/OpenRC-сервис.
#
#  Supported:
#    Ubuntu 20.04+ / Debian 11+
#    CentOS 8+ / RHEL 8+ / Rocky / Alma
#    Fedora 36+
#    Arch Linux
#    Alpine 3.17+
#    openSUSE Leap 15.4+ / Tumbleweed
# ============================================================================

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────

INSTALL_DIR="/opt/nft-gift-bot"
SERVICE_NAME="nft-gift-bot"
BINARY_NAME="nft-gift-bot"

# GitHub repo
GITHUB_REPO="${GITHUB_REPO:-fitymico/nft-gift-bot-release}"

# ── Colours & helpers ────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { printf "${CYAN}[INFO]${NC}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
err()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
die()   { err "$*"; exit 1; }

ask() {
    local prompt="$1" default="${2:-}" value
    if [[ -n "$default" ]]; then
        printf "${BOLD}%s${NC} [%s]: " "$prompt" "$default" >&2
    else
        printf "${BOLD}%s${NC}: " "$prompt" >&2
    fi
    read -r value </dev/tty
    echo "${value:-$default}"
}

ask_secret() {
    local prompt="$1" default="${2:-}" value
    if [[ -n "$default" ]]; then
        local masked="${default:0:4}****${default: -4}"
        printf "${BOLD}%s${NC} [%s]: " "$prompt" "$masked" >&2
    else
        printf "${BOLD}%s${NC}: " "$prompt" >&2
    fi
    read -r value </dev/tty
    echo "${value:-$default}"
}

# ── Check if installed ───────────────────────────────────────────────────────

is_installed() {
    [[ -f "$INSTALL_DIR/$BINARY_NAME" ]] || [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]] || [[ -f "/etc/init.d/${SERVICE_NAME}" ]]
}

is_service_running() {
    if command -v systemctl &>/dev/null; then
        systemctl is-active "$SERVICE_NAME" &>/dev/null
    elif command -v rc-service &>/dev/null; then
        rc-service "$SERVICE_NAME" status &>/dev/null
    else
        return 1
    fi
}

# ── Menu for existing installation ───────────────────────────────────────────

show_installed_menu() {
    echo
    printf "${BOLD}${YELLOW}══════════════════════════════════════════════════${NC}\n"
    printf "${BOLD}${YELLOW}      NFT Gift Bot уже установлен                 ${NC}\n"
    printf "${BOLD}${YELLOW}══════════════════════════════════════════════════${NC}\n"
    echo
    echo "  Каталог: $INSTALL_DIR"

    if is_service_running; then
        printf "  Статус:  ${GREEN}запущен${NC}\n"
    else
        printf "  Статус:  ${RED}остановлен${NC}\n"
    fi
    echo
    echo "  Выберите действие:"
    echo
    printf "    ${BOLD}1${NC}) Переустановить (обновить бинарник)\n"
    printf "    ${BOLD}2${NC}) Изменить настройки (.env)\n"
    printf "    ${BOLD}3${NC}) Удалить полностью\n"
    printf "    ${BOLD}4${NC}) Выход\n"
    echo

    local choice
    printf "${BOLD}Ваш выбор [1-4]:${NC} "
    read -r choice </dev/tty

    case "$choice" in
        1)
            info "Переустановка..."
            return 0  # continue with install
            ;;
        2)
            edit_config_interactive
            exit 0
            ;;
        3)
            uninstall_bot
            exit 0
            ;;
        4|"")
            info "Выход без изменений"
            exit 0
            ;;
        *)
            warn "Неверный выбор"
            exit 1
            ;;
    esac
}

# ── Interactive config editor ────────────────────────────────────────────────

edit_config_interactive() {
    echo
    printf "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}\n"
    printf "${BOLD}${CYAN}          Изменение настроек                      ${NC}\n"
    printf "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}\n"
    echo

    # Load existing config
    local OLD_BOT_TOKEN="" OLD_LICENSE_KEY=""
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        set +u
        source "$INSTALL_DIR/.env" 2>/dev/null || true
        OLD_BOT_TOKEN="${BOT_TOKEN:-}"
        OLD_LICENSE_KEY="${LICENSE_KEY:-}"
        set -u
    fi

    echo "  Текущие значения показаны в скобках."
    echo "  Нажмите Enter, чтобы оставить без изменений."
    echo

    echo "  1/2. Лицензионный ключ"
    echo "       Формат: SB-123456789-XXXXXXXX"
    CFG_LICENSE_KEY=$(ask_secret "       Вставьте ключ" "$OLD_LICENSE_KEY")
    [[ -z "$CFG_LICENSE_KEY" ]] && die "LICENSE_KEY обязателен"
    echo

    echo "  2/2. Telegram Bot Token"
    CFG_BOT_TOKEN=$(ask_secret "       Вставьте токен" "$OLD_BOT_TOKEN")
    [[ -z "$CFG_BOT_TOKEN" ]] && die "BOT_TOKEN обязателен"
    echo

    write_env

    # Restart service if running
    if is_service_running; then
        info "Перезапускаю сервис..."
        if command -v systemctl &>/dev/null; then
            systemctl restart "$SERVICE_NAME"
        elif command -v rc-service &>/dev/null; then
            rc-service "$SERVICE_NAME" restart
        fi
        ok "Сервис перезапущен с новыми настройками"
    else
        ok "Настройки сохранены. Запустите сервис вручную."
    fi
}

# ── Uninstall ────────────────────────────────────────────────────────────────

uninstall_bot() {
    echo
    printf "${BOLD}${RED}══════════════════════════════════════════════════${NC}\n"
    printf "${BOLD}${RED}              Удаление NFT Gift Bot               ${NC}\n"
    printf "${BOLD}${RED}══════════════════════════════════════════════════${NC}\n"
    echo

    printf "${BOLD}Вы уверены? Все данные будут удалены. [y/N]:${NC} "
    local confirm
    read -r confirm </dev/tty

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        info "Отменено"
        return
    fi

    info "Останавливаю сервис..."
    if command -v systemctl &>/dev/null; then
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload 2>/dev/null || true
    fi

    if command -v rc-service &>/dev/null; then
        rc-service "$SERVICE_NAME" stop 2>/dev/null || true
        rc-update del "$SERVICE_NAME" 2>/dev/null || true
        rm -f "/etc/init.d/${SERVICE_NAME}"
    fi

    info "Удаляю файлы..."
    rm -rf "$INSTALL_DIR"

    ok "NFT Gift Bot полностью удалён"
}

# ── Detect distribution ──────────────────────────────────────────────────────

DISTRO=""

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "${ID:-}" in
            ubuntu|debian|linuxmint|pop)       DISTRO="debian"  ;;
            centos|rhel|rocky|almalinux)       DISTRO="rhel"    ;;
            fedora)                            DISTRO="fedora"  ;;
            arch|manjaro|endeavouros)          DISTRO="arch"    ;;
            alpine)                            DISTRO="alpine"  ;;
            opensuse*|sles)                    DISTRO="suse"    ;;
            *)
                if command -v apt-get &>/dev/null; then DISTRO="debian"
                elif command -v dnf &>/dev/null; then DISTRO="fedora"
                elif command -v yum &>/dev/null; then DISTRO="rhel"
                elif command -v pacman &>/dev/null; then DISTRO="arch"
                elif command -v apk &>/dev/null; then DISTRO="alpine"
                elif command -v zypper &>/dev/null; then DISTRO="suse"
                fi
                ;;
        esac
    fi

    if [[ -z "$DISTRO" ]]; then
        die "Не удалось определить дистрибутив. Установите бот вручную."
    fi

    info "Дистрибутив: $DISTRO"
}

# ── Install curl ─────────────────────────────────────────────────────────────

ensure_curl() {
    if command -v curl &>/dev/null; then return; fi
    info "Устанавливаю curl..."
    case "$DISTRO" in
        debian)  apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1 ;;
        fedora)  dnf install -y -q curl >/dev/null 2>&1 ;;
        rhel)    yum install -y -q curl >/dev/null 2>&1 ;;
        arch)    pacman -Sy --noconfirm curl >/dev/null 2>&1 ;;
        alpine)  apk add -q curl >/dev/null 2>&1 ;;
        suse)    zypper -q install -y curl >/dev/null 2>&1 ;;
    esac
}

# ── Detect arch ──────────────────────────────────────────────────────────────

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)   echo "amd64" ;;
        aarch64|arm64)  echo "arm64" ;;
        *)              die "Архитектура $arch не поддерживается" ;;
    esac
}

# ── Download binary ──────────────────────────────────────────────────────────

download_binary() {
    local arch="$1"
    local download_url="https://github.com/${GITHUB_REPO}/raw/main/${BINARY_NAME}-linux-${arch}"

    info "Скачиваю бинарник..."
    info "URL: $download_url"

    mkdir -p "$INSTALL_DIR"

    if ! curl -fsSL "$download_url" -o "$INSTALL_DIR/$BINARY_NAME"; then
        die "Не удалось скачать бинарник. Проверьте URL: $download_url"
    fi

    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    ok "Бинарник загружен: $INSTALL_DIR/$BINARY_NAME"
}

# ── Collect config ───────────────────────────────────────────────────────────

CFG_BOT_TOKEN=""
CFG_ADMIN_ID=""
CFG_LICENSE_KEY=""

collect_config() {
    echo
    printf "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}\n"
    printf "${BOLD}${CYAN}          Настройка NFT Gift Bot                  ${NC}\n"
    printf "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}\n"
    echo

    # Load existing config if present
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        warn "Найден существующий .env — значения будут использованы как умолчания"
        set +u
        source "$INSTALL_DIR/.env" 2>/dev/null || true
        set -u
    fi

    echo "  1/2. Лицензионный ключ"
    echo "       Получен после оплаты SELF-HOST подписки в Service-Bot."
    echo "       Формат: SB-123456789-XXXXXXXX"
    CFG_LICENSE_KEY=$(ask "       Вставьте ключ" "${LICENSE_KEY:-}")
    [[ -z "$CFG_LICENSE_KEY" ]] && die "LICENSE_KEY обязателен"
    echo

    echo "  2/2. Telegram Bot"
    echo "       Создайте бота через @BotFather и скопируйте токен."
    CFG_BOT_TOKEN=$(ask "       Вставьте токен" "${BOT_TOKEN:-}")
    [[ -z "$CFG_BOT_TOKEN" ]] && die "BOT_TOKEN обязателен"
    echo
}

write_env() {
    cat > "$INSTALL_DIR/.env" <<ENVEOF
# NFT Gift Bot — Configuration
# Generated by install.sh at $(date -Iseconds 2>/dev/null || date)

LICENSE_KEY=${CFG_LICENSE_KEY}
BOT_TOKEN=${CFG_BOT_TOKEN}
ENVEOF

    chmod 600 "$INSTALL_DIR/.env"
    ok "Конфигурация сохранена в $INSTALL_DIR/.env"
}

# ── Create service ───────────────────────────────────────────────────────────

create_service() {
    if command -v systemctl &>/dev/null; then
        create_systemd_service
    elif command -v rc-service &>/dev/null; then
        create_openrc_service
    else
        warn "Ни systemd, ни OpenRC не обнаружены."
        warn "Запускайте вручную: $INSTALL_DIR/$BINARY_NAME"
    fi
}

create_systemd_service() {
    info "Создаю systemd-сервис..."

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<SVCEOF
[Unit]
Description=NFT Gift Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/$BINARY_NAME
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    systemctl restart "$SERVICE_NAME"

    ok "Сервис '$SERVICE_NAME' создан и запущен"
}

create_openrc_service() {
    info "Создаю OpenRC-сервис..."

    cat > "/etc/init.d/${SERVICE_NAME}" <<RCEOF
#!/sbin/openrc-run

name="NFT Gift Bot"
description="NFT Gift Bot"
command="$INSTALL_DIR/$BINARY_NAME"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
directory="$INSTALL_DIR"
output_log="/var/log/\${RC_SVCNAME}.log"
error_log="/var/log/\${RC_SVCNAME}.err"

depend() {
    need net
}

start_pre() {
    export \$(grep -v '^#' $INSTALL_DIR/.env | xargs)
}
RCEOF

    chmod +x "/etc/init.d/${SERVICE_NAME}"
    rc-update add "$SERVICE_NAME" default 2>/dev/null
    rc-service "$SERVICE_NAME" restart 2>/dev/null

    ok "OpenRC-сервис '$SERVICE_NAME' создан и запущен"
}

# ── Uninstall script ─────────────────────────────────────────────────────────

create_uninstall() {
    cat > "$INSTALL_DIR/uninstall.sh" <<'UNEOF'
#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="nft-gift-bot"
INSTALL_DIR="/opt/nft-gift-bot"

echo "Удаляю NFT Gift Bot..."

if command -v systemctl &>/dev/null; then
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload 2>/dev/null || true
fi

if command -v rc-service &>/dev/null; then
    rc-service "$SERVICE_NAME" stop 2>/dev/null || true
    rc-update del "$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/init.d/${SERVICE_NAME}"
fi

rm -rf "$INSTALL_DIR"
echo "NFT Gift Bot удалён."
UNEOF

    chmod +x "$INSTALL_DIR/uninstall.sh"
}

# ── Summary ──────────────────────────────────────────────────────────────────

print_summary() {
    echo
    printf "${BOLD}${GREEN}══════════════════════════════════════════════════${NC}\n"
    printf "${BOLD}${GREEN}         Установка завершена!                      ${NC}\n"
    printf "${BOLD}${GREEN}══════════════════════════════════════════════════${NC}\n"
    echo
    echo "  Каталог:    $INSTALL_DIR"
    echo "  Бинарник:   $INSTALL_DIR/$BINARY_NAME"
    echo "  Конфиг:     $INSTALL_DIR/.env"
    echo "  Удаление:   sudo bash $INSTALL_DIR/uninstall.sh"
    echo
    printf "${CYAN}  Управление:${NC}\n"

    if command -v systemctl &>/dev/null; then
        echo "    sudo systemctl status  $SERVICE_NAME    # статус"
        echo "    sudo systemctl restart $SERVICE_NAME    # перезапуск"
        echo "    sudo systemctl stop    $SERVICE_NAME    # остановка"
        echo "    sudo journalctl -u $SERVICE_NAME -f     # логи"
    elif command -v rc-service &>/dev/null; then
        echo "    sudo rc-service $SERVICE_NAME status     # статус"
        echo "    sudo rc-service $SERVICE_NAME restart    # перезапуск"
        echo "    sudo rc-service $SERVICE_NAME stop       # остановка"
        echo "    tail -f /var/log/${SERVICE_NAME}.log     # логи"
    else
        echo "    $INSTALL_DIR/$BINARY_NAME               # запуск"
    fi

    echo
    printf "${CYAN}  Авторизация Telegram:${NC}\n"
    echo "    После запуска откройте бота в Telegram и отправьте /auth"
    echo "    Бот запросит номер телефона и код подтверждения."
    echo

    printf "${CYAN}  Изменение настроек:${NC}\n"
    echo "    1. Отредактируйте $INSTALL_DIR/.env"
    echo "    2. sudo systemctl restart $SERVICE_NAME"
    echo

    printf "${CYAN}  Обновление:${NC}\n"
    echo "    Повторно запустите этот скрипт — он обновит бинарник,"
    echo "    сохранив существующий .env"
    echo
}

# ══════════════════════════════════════════════════════════════════════════════
#                              MAIN
# ══════════════════════════════════════════════════════════════════════════════

main() {
    echo
    printf "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}\n"
    printf "${BOLD}${CYAN}      NFT Gift Bot — Installer                    ${NC}\n"
    printf "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}\n"
    echo

    # Check root
    if [[ $EUID -ne 0 ]]; then
        die "Запустите скрипт от root:\n  sudo bash install.sh"
    fi

    # Check if already installed
    if is_installed; then
        show_installed_menu
        # If we reach here, user chose to reinstall
    fi

    detect_distro
    ensure_curl

    local arch
    arch=$(detect_arch)
    info "Архитектура: $arch"

    download_binary "$arch"
    collect_config
    write_env
    mkdir -p "$INSTALL_DIR/data"
    create_service
    create_uninstall
    print_summary
}

main "$@"

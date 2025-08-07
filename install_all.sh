#!/bin/bash

# ============================================
# Secure 3x-ui Installer (Ultimate Edition)
# Автор: Max Galzer | https://github.com/maxgalzer
# ============================================

set -e

# --- Отключаем интерактивные needrestart и лишний мусор в выводе apt ---
export NEEDRESTART_MODE=a

if [[ "$EUID" -ne 0 ]]; then
  echo "‼️ Скрипт нужно запускать от root"
  exit 1
fi

# 1. Сбор параметров
echo "🔧 Укажи параметры установки:"
read -rp "➡️  Новый SSH-порт (не 22): " NEW_SSH_PORT
read -rp "➡️  Порт панели 3x-ui: " XUI_PANEL_PORT
read -rp "➡️  Порт инбаунда: " XUI_INBOUND_PORT
read -rp "➡️  Домен (для SSL): " DOMAIN_NAME

read -rp "➡️  Устанавливать уведомления в Telegram о продлении SSL? (y/n): " TG_ENABLE
if [[ "$TG_ENABLE" =~ ^[Yy]$ ]]; then
    read -rp "    ➡️  Telegram Bot Token: " TELEGRAM_TOKEN
    read -rp "    ➡️  Telegram Chat ID: " TELEGRAM_CHAT_ID
    TG_STATUS="✅ Включены"
else
    TELEGRAM_TOKEN=""
    TELEGRAM_CHAT_ID=""
    TG_STATUS="❌ Отключены"
fi

echo ""
echo "📋 Подтвердите параметры:"
echo "SSH-порт:          $NEW_SSH_PORT"
echo "Порт панели:       $XUI_PANEL_PORT"
echo "Порт инбаунда:     $XUI_INBOUND_PORT"
echo "Домен:             $DOMAIN_NAME"
echo "Telegram-нотификации: $TG_STATUS"
[[ -n "$TELEGRAM_TOKEN" ]] && echo "Telegram Token:    $TELEGRAM_TOKEN"
[[ -n "$TELEGRAM_CHAT_ID" ]] && echo "Telegram Chat ID:  $TELEGRAM_CHAT_ID"
read -rp "Продолжить? (y/n): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 1

# 2. Установка зависимостей
echo "[*] Обновляем пакеты и ставим зависимости..."
apt update -y
apt install -y curl socat ufw git lsof

# 3. ICMP-правила UFW
echo "[*] Настраиваем фильтрацию ICMP в UFW..."
RULES_FILE="/etc/ufw/before.rules"
cp "$RULES_FILE" "${RULES_FILE}.bak"
awk '
  BEGIN { skip_input = 0; skip_forward = 0 }
  /# ok icmp codes for INPUT/ {
    print;
    print "-A ufw-before-input -p icmp --icmp-type destination-unreachable -j DROP";
    print "-A ufw-before-input -p icmp --icmp-type time-exceeded -j DROP";
    print "-A ufw-before-input -p icmp --icmp-type parameter-problem -j DROP";
    print "-A ufw-before-input -p icmp --icmp-type echo-request -j DROP";
    print "-A ufw-before-input -p icmp --icmp-type source-quench -j DROP";
    skip_input = 5;
    next
  }
  /# ok icmp code for FORWARD/ {
    print;
    print "-A ufw-before-forward -p icmp --icmp-type destination-unreachable -j DROP";
    print "-A ufw-before-forward -p icmp --icmp-type time-exceeded -j DROP";
    print "-A ufw-before-forward -p icmp --icmp-type parameter-problem -j DROP";
    print "-A ufw-before-forward -p icmp --icmp-type echo-request -j DROP";
    skip_forward = 4;
    next
  }
  skip_input > 0 { skip_input--; next }
  skip_forward > 0 { skip_forward--; next }
  { print }
' "${RULES_FILE}.bak" > "$RULES_FILE"

# 4. Включение UFW и разрешение SSH-порта
echo "[*] Включаем UFW и разрешаем текущий SSH-порт..."

# Сначала пробуем получить реально используемый порт из процессов
CURRENT_PORT=$(ss -tnlp | grep -w sshd | awk -F':' '/sshd/ && $NF ~ /^[0-9]+$/ {print $NF; exit}')
# Если не найден — читаем из конфига (более надежно)
if [[ -z "$CURRENT_PORT" ]]; then
  CURRENT_PORT=$(grep -E '^Port ' /etc/ssh/sshd_config | head -n1 | awk '{print $2}')
fi
# Если все равно пусто — используем 22 (по дефолту)
if [[ -z "$CURRENT_PORT" ]]; then
  CURRENT_PORT=22
fi

ufw allow "$CURRENT_PORT"/tcp
ufw disable
ufw enable

# 5. Установка 3x-ui
echo "[*] Устанавливаем 3x-ui..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# 6. Открытие портов
ufw allow "$XUI_PANEL_PORT"/tcp
ufw allow "$XUI_INBOUND_PORT"/tcp
ufw allow 80/tcp

# 7. SSL: acme.sh и сертификат
echo "[*] Останавливаем x-ui для SSL..."
systemctl stop x-ui || true
sleep 2

if [ ! -d "$HOME/.acme.sh" ]; then
  curl https://get.acme.sh | sh
  source ~/.bashrc || true
fi

echo "[*] Генерируем SSL для $DOMAIN_NAME..."
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN_NAME" --force

if [ ! -f "/root/.acme.sh/$DOMAIN_NAME/fullchain.cer" ]; then
    echo "❌ Не удалось получить SSL сертификат. Проверь домен!"
    exit 1
fi

echo "[*] Копируем сертификаты для x-ui..."
cp "/root/.acme.sh/$DOMAIN_NAME/fullchain.cer" "/usr/local/x-ui/bin/cert.crt"
cp "/root/.acme.sh/$DOMAIN_NAME/$DOMAIN_NAME.key" "/usr/local/x-ui/bin/private.key"

systemctl start x-ui
sleep 2
ufw deny 80/tcp

# 8. Renew SSL + Telegram (опционально)
if [[ "$TG_ENABLE" =~ ^[Yy]$ ]]; then
cat <<EOF > /root/renew_ssl.sh
#!/bin/bash

export NEEDRESTART_MODE=a
LOGFILE="/var/log/ssl_renew.log"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
DOMAIN_NAME="${DOMAIN_NAME}"

NOW=\$(date '+%Y-%m-%d %H:%M:%S')
SERVER_IP=\$(curl -s ifconfig.me)
STATUS=""

{
  echo ""
  echo "===== [\${NOW}] 🔐 SSL ОБНОВЛЕНИЕ ====="
  echo "[IP] \${SERVER_IP}"
  ufw allow 80/tcp
  ~/.acme.sh/acme.sh --issue --standalone -d "\$DOMAIN_NAME" --force
  RENEW_EXIT=\$?
  cp "/root/.acme.sh/\$DOMAIN_NAME/fullchain.cer" "/usr/local/x-ui/bin/cert.crt"
  cp "/root/.acme.sh/\$DOMAIN_NAME/\$DOMAIN_NAME.key" "/usr/local/x-ui/bin/private.key"
  systemctl restart x-ui
  ufw deny 80/tcp

  if [[ \$RENEW_EXIT -eq 0 ]]; then
    STATUS="✅ УСПЕШНО"
  else
    STATUS="❌ ОШИБКА (Код: \$RENEW_EXIT)"
  fi

  echo "[ACME] Список сертификатов:"
  ~/.acme.sh/acme.sh --list

  echo "===== Завершено [\${NOW}] \$STATUS ====="
} >> "\$LOGFILE" 2>&1

CERT_LIST=\$( ~/.acme.sh/acme.sh --list | tail -n +2 | awk '{printf "%s — %s ➜ %s\\n", \$1, \$4, \$5}' | head -n 5 )

MESSAGE=\$(cat <<EOM
🔐 <b>SSL обновление завершено</b>
📅 <b>\${NOW}</b>
🌐 <b>IP:</b> <code>\${SERVER_IP}</code>
📊 <b>Статус:</b> \$STATUS

<pre>\$CERT_LIST</pre>
EOM
)

curl -s -X POST "https://api.telegram.org/bot\${TELEGRAM_TOKEN}/sendMessage" \
  -d chat_id="\${TELEGRAM_CHAT_ID}" \
  -d text="\$MESSAGE" \
  -d parse_mode="HTML"
EOF

chmod +x /root/renew_ssl.sh
(crontab -l 2>/dev/null | grep -v 'renew_ssl.sh'; echo "22 4 * * * /root/renew_ssl.sh") | crontab -
fi

# 9. В самом конце: меняем SSH-порт
echo "[*] Меняем SSH-порт на $NEW_SSH_PORT..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"
sed -i "s/^#\?Port .*/Port $NEW_SSH_PORT/" "$SSHD_CONFIG"
ufw allow "$NEW_SSH_PORT"/tcp

echo "[*] Проверяем доступность нового SSH-порта..."
systemctl reload ssh
sleep 2
if nc -z 127.0.0.1 "$NEW_SSH_PORT"; then
  echo "[✔] Порт $NEW_SSH_PORT доступен. Перезапускаем SSH..."
  systemctl restart ssh
  echo "[✅] Установка завершена. Подключайся по порту: $NEW_SSH_PORT"
  SSH_CHANGED=1
else
  echo "[❌] Новый SSH-порт недоступен. Возвращаем старый конфиг..."
  mv "${SSHD_CONFIG}.bak" "$SSHD_CONFIG"
  systemctl reload ssh
  SSH_CHANGED=0
fi

# --- Итоговый красивый отчёт ---
clear
echo -e "\n\033[1;34m==========  УСТАНОВКА ЗАВЕРШЕНА  ==========\033[0m\n"
echo -e "  \033[1;32m✔ Порт подключения к серверу изменён\033[0m"
echo -e "  \033[1;32m✔ 3x-ui установлен и запущен\033[0m"
echo -e "  \033[1;32m✔ SSL-сертификат для домена выдан и подключён\033[0m"
if [[ "$TG_ENABLE" =~ ^[Yy]$ ]]; then
  echo -e "  \033[1;32m✔ Настроен крон для автопродления и уведомления в Telegram\033[0m"
else
  echo -e "  \033[1;33m✘ Уведомления в Telegram не подключены (по вашему выбору)\033[0m"
fi
echo -e "  \033[1;32m✔ Открыты порты:\033[0m"
echo -e "       - SSH (новый):   \033[1;36m$NEW_SSH_PORT\033[0m"
echo -e "       - 3x-ui панель:  \033[1;36m$XUI_PANEL_PORT\033[0m"
echo -e "       - Инбаунд:       \033[1;36m$XUI_INBOUND_PORT\033[0m"
echo -e "  \033[1;32m✔ Остальные порты закрыты (UFW активен)\033[0m"
if [[ "$SSH_CHANGED" == "1" ]]; then
  echo -e "\n  \033[1;36mПодключайтесь по новому порту SSH: $NEW_SSH_PORT\033[0m"
else
  echo -e "\n  \033[1;31mSSH-порт остался прежним! Проверьте настройки вручную!\033[0m"
fi
echo -e "\n\033[1;34m===========================================\033[0m\n"

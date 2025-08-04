#!/bin/bash

# ============================================
# Secure 3x-ui Installer — интерактивный скрипт
# Автор: Max Galzer | https://github.com/maxgalzer
# ============================================

# Проверка на root
if [[ "$EUID" -ne 0 ]]; then
  echo "‼️ Скрипт нужно запускать от root"
  exit 1
fi

# ───── Ввод параметров ─────
echo "🔧 Укажи параметры установки:"
read -rp "➡️  Новый SSH-порт (не 22): " NEW_SSH_PORT
read -rp "➡️  Порт панели 3x-ui: " XUI_PANEL_PORT
read -rp "➡️  Порт инбаунда: " XUI_INBOUND_PORT
read -rp "➡️  Домен (для SSL): " DOMAIN_NAME

echo ""
echo "📋 Подтвердите параметры:"
echo "SSH-порт:          $NEW_SSH_PORT"
echo "Порт панели:       $XUI_PANEL_PORT"
echo "Порт инбаунда:     $XUI_INBOUND_PORT"
echo "Домен:             $DOMAIN_NAME"
read -rp "Продолжить? (y/n): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 1

# ───── Шаг 1: Обновление ─────
echo "[*] Обновляем пакеты..."
apt update -y

# ───── Шаг 2: Настройка ICMP ─────
echo "[*] Настраиваем фильтрацию ICMP в UFW..."
RULES_FILE="/etc/ufw/before.rules"
cp "$RULES_FILE" "${RULES_FILE}.bak"

awk '
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

# ───── Шаг 3: Включение UFW и текущий SSH-порт ─────
echo "[*] Включаем UFW и разрешаем текущий SSH-порт..."
CURRENT_PORT=$(ss -tnlp | grep sshd | awk -F':' '/sshd/ && $NF ~ /^[0-9]+$/ {print $NF; exit}')
ufw allow "$CURRENT_PORT"/tcp
ufw disable
ufw enable

# ───── Шаг 4: Установка 3x-ui ─────
echo "[*] Устанавливаем 3x-ui..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# ───── Шаг 5: Открытие портов ─────
ufw allow "$XUI_PANEL_PORT"/tcp
ufw allow 80/tcp

# ───── Шаг 6: Настройка домена ─────
echo "[*] Настраиваем домен в панели..."
x-ui <<EOF
18
1
$DOMAIN_NAME

N
Y
EOF

# ───── Шаг 7: Закрытие 80 и cron ─────
ufw deny 80/tcp
echo "[*] Добавляем cron для обновления SSL..."
CRON_JOB='22 4 * * * ufw allow 80/tcp && "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" > /dev/null && ufw deny 80/tcp'
(crontab -l 2>/dev/null | grep -v 'acme.sh.*--cron'; echo "$CRON_JOB") | crontab -

# ───── Шаг 8: Открываем порт инбаунда ─────
ufw allow "$XUI_INBOUND_PORT"/tcp

# ───── Шаг 9: Смена SSH-порта ─────
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
else
  echo "[❌] Новый SSH-порт недоступен. Возвращаем старый конфиг..."
  mv "${SSHD_CONFIG}.bak" "$SSHD_CONFIG"
  systemctl reload ssh
fi


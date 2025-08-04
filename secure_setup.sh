#!/bin/bash

# Скрипт безопасной настройки сервера с 3x-ui, UFW и сменой SSH порта
# Автор: Max

# ========== ПЕРЕМЕННЫЕ ==========

NEW_SSH_PORT=2222                  # Укажи новый SSH порт (≠ 22)
XUI_PANEL_PORT=54321               # Порт для панели 3x-ui
XUI_INBOUND_PORT=12345             # Порт инбаунда
DOMAIN_NAME="your.domain.com"      # Укажи домен для 3x-ui

# ========== ПРОВЕРКИ ==========

if [[ "$EUID" -ne 0 ]]; then
  echo "‼️ Запусти скрипт от root (sudo)"
  exit 1
fi

# ========== ШАГ 1: apt update ==========

echo "[*] Обновляем пакеты..."
apt update -y

# ========== ШАГ 2: настройка ICMP ==========

echo "[*] Настраиваем ICMP-фильтрацию в UFW..."
BEFORE_RULES="/etc/ufw/before.rules"
cp -f "$BEFORE_RULES" "${BEFORE_RULES}.bak"

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
' "${BEFORE_RULES}.bak" > "$BEFORE_RULES"

# ========== ШАГ 3: UFW перезапуск ==========

echo "[*] Перезапускаем UFW..."
ufw disable
ufw enable

# ========== ШАГ 4: SSH-порт (текущий) ==========

echo "[*] Разрешаем текущий SSH-порт (безопасность соединения)..."
CURRENT_PORT=$(ss -tnlp | grep sshd | awk -F':' '/sshd/ && $NF ~ /^[0-9]+$/ {print $NF; exit}')
ufw allow "$CURRENT_PORT"/tcp

# ========== ШАГ 5: Установка 3x-ui ==========

echo "[*] Устанавливаем 3x-ui..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# ========== ШАГ 6: Открываем порты ==========

echo "[*] Открываем порты для панели и сертификации..."
ufw allow "$XUI_PANEL_PORT"/tcp
ufw allow 80/tcp

# ========== ШАГ 7: Настройка домена в 3x-ui ==========

echo "[*] Настраиваем домен $DOMAIN_NAME в 3x-ui..."
x-ui <<EOF
18
1
$DOMAIN_NAME

N
Y
EOF

# ========== ШАГ 8: Закрываем порт 80 ==========

echo "[*] Закрываем порт 80 (сертификат получен)..."
ufw deny 80/tcp

# ========== ШАГ 9: Установка cron для автопродления ==========

echo "[*] Добавляем cron-задачу для продления сертификата..."

CRON_JOB='22 4 * * * ufw allow 80/tcp && "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" > /dev/null && ufw deny 80/tcp'
(crontab -l 2>/dev/null | grep -v 'acme.sh.*--cron'; echo "$CRON_JOB") | crontab -

# ========== ШАГ 10: Открываем порт инбаунда ==========

echo "[*] Открываем порт инбаунда: $XUI_INBOUND_PORT"
ufw allow "$XUI_INBOUND_PORT"/tcp

# ========== ШАГ 11: Замена SSH-порта ==========

echo "[*] Настраиваем новый SSH-порт: $NEW_SSH_PORT"
SSHD_CONFIG="/etc/ssh/sshd_config"
cp -f "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"
sed -i "s/^#\?Port .*/Port $NEW_SSH_PORT/" "$SSHD_CONFIG"
ufw allow "$NEW_SSH_PORT"/tcp

# ========== ШАГ 12: Проверка нового SSH-порта ДО перезапуска ==========

echo "[*] Проверка доступности нового SSH-порта ($NEW_SSH_PORT)..."
systemctl reload ssh

sleep 2
if nc -z 127.0.0.1 "$NEW_SSH_PORT"; then
  echo "[✔] Новый SSH-порт $NEW_SSH_PORT работает. Перезапускаем SSH..."
  systemctl restart ssh
  echo "[✅] Готово. Подключайся по SSH на порт: $NEW_SSH_PORT"
else
  echo "[‼️] Ошибка! Порт $NEW_SSH_PORT не доступен. Оставляем старый порт."
  mv "${SSHD_CONFIG}.bak" "$SSHD_CONFIG"
  systemctl reload ssh
fi

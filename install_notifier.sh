#!/bin/bash

# Step 1: Prompt for Telegram credentials
echo "\U0001F4AC Введите TELEGRAM_TOKEN:"
read -r TELEGRAM_TOKEN
echo "\U0001F464 Введите TELEGRAM_CHAT_ID:"
read -r TELEGRAM_CHAT_ID

# Step 2: Create renew_ssl.sh
cat <<EOF > /root/renew_ssl.sh
#!/bin/bash

LOGFILE="/var/log/ssl_renew.log"
TELEGRAM_TOKEN="$TELEGRAM_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"

NOW=\$(date '+%Y-%m-%d %H:%M:%S')
SERVER_IP=\$(curl -s ifconfig.me)
STATUS=""

{
  echo ""
  echo "===== [\$NOW] \U0001F510 SSL ОБНОВЛЕНИЕ ====="
  echo "[IP] \$SERVER_IP"
  ufw allow 80/tcp
  /root/.acme.sh/acme.sh --cron --home /root/.acme.sh
  RENEW_EXIT=\$?
  ufw deny 80/tcp

  if [[ \$RENEW_EXIT -eq 0 ]]; then
    STATUS="✅ УСПЕШНО"
  else
    STATUS="❌ ОШИБКА (Код: \$RENEW_EXIT)"
  fi

  echo "[ACME] Список сертификатов:"
  /root/.acme.sh/acme.sh --list

  echo "===== Завершено [\$NOW] \$STATUS ====="
} >> "\$LOGFILE" 2>&1

CERT_LIST=\$( /root/.acme.sh/acme.sh --list | tail -n +2 | awk '{printf "%s — %s ➔ %s\\n", \$1, \$4, \$5}' | head -n 5 )

MESSAGE=\$(cat <<EOM
<b>\U0001F510 SSL обновление завершено</b>
\U0001F4C5 <b>\$NOW</b>
\U0001F310 <b>IP:</b> <code>\$SERVER_IP</code>
\U0001F4CA <b>Статус:</b> \$STATUS

<pre>\$CERT_LIST</pre>
EOM
)

curl -s -X POST "https://api.telegram.org/bot\${TELEGRAM_TOKEN}/sendMessage" \
  -d chat_id="\${TELEGRAM_CHAT_ID}" \
  -d text="\$MESSAGE" \
  -d parse_mode="HTML"
EOF

# Step 3: Make the script executable
chmod +x /root/renew_ssl.sh

# Step 4: Replace crontab
crontab -l | grep -v renew_ssl.sh > temp_cron || true
echo "22 4 * * * /root/renew_ssl.sh" >> temp_cron
crontab temp_cron
rm temp_cron

# Step 5: Send test notification
/root/renew_ssl.sh

echo -e "
\U0001F389 Скрипт установлен и тестовое уведомление отправлено."

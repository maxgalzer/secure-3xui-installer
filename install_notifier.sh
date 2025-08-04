#!/bin/bash

echo "🔑 Введите TELEGRAM_TOKEN:"
read -r TELEGRAM_TOKEN
echo "💬 Введите TELEGRAM_CHAT_ID:"
read -r TELEGRAM_CHAT_ID

cat <<EOF > /root/renew_ssl.sh
#!/bin/bash

LOGFILE="/var/log/ssl_renew.log"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"

NOW=\$(date '+%Y-%m-%d %H:%M:%S')
SERVER_IP=\$(curl -s ifconfig.me)
STATUS=""

{
  echo ""
  echo "===== [\${NOW}] 🔐 SSL ОБНОВЛЕНИЕ ====="
  echo "[IP] \${SERVER_IP}"
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

  echo "===== Завершено [\${NOW}] \$STATUS ====="
} >> "\$LOGFILE" 2>&1

CERT_LIST=\$( /root/.acme.sh/acme.sh --list | tail -n +2 | awk '{printf "%s — %s ➜ %s\\n", \$1, \$4, \$5}' | head -n 5 )

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

# Обновление crontab
crontab -l 2>/dev/null | grep -v 'renew_ssl.sh' > /tmp/cron.tmp
echo "22 4 * * * /root/renew_ssl.sh" >> /tmp/cron.tmp
crontab /tmp/cron.tmp
rm /tmp/cron.tmp

# Пробный запуск
echo "🚀 Запускаем пробное обновление SSL..."
bash /root/renew_ssl.sh

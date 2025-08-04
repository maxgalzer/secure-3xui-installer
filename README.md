# 🔐 Secure 3x-ui Installer

Безопасная автоматическая установка 3x-ui с настройкой:

- Защита ICMP
- Настройка UFW
- Смена SSH-порта
- Установка 3x-ui
- SSL через ACME + cron для продления

---

## 🚀 Быстрый запуск

```bash
bash <(curl -Ls https://raw.githubusercontent.com/maxgalzer/secure-3xui-installer/main/secure_setup.sh)
```
⚠️ После запуска пропиши переменные для secure_setup.sh:
NEW_SSH_PORT, XUI_PANEL_PORT, XUI_INBOUND_PORT, DOMAIN_NAME

---

## 🌐 Управление портом 80 (для SSL)

📖 Открыть порт 80 (для получения сертификата):

```bash
ufw allow 80/tcp
```

🔒 Закрыть порт 80 (после получения):

```bash
ufw deny 80/tcp
```

---

## 🔔 Установка Telegram-уведомлений

```bash
bash <(curl -Ls https://raw.githubusercontent.com/maxgalzer/secure-3xui-installer/main/install_notifier.sh)
```

- Скрипт создаёт `/root/renew_ssl.sh`
- Добавляет cron-задачу `22 4 * * *`
- Отправляет тестовое уведомление в Telegram

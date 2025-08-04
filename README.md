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

Перед запуском отредактируй переменные в secure_setup.sh:
NEW_SSH_PORT, XUI_PANEL_PORT, XUI_INBOUND_PORT, DOMAIN_NAME

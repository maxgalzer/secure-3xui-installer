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
- NEW_SSH_PORT, XUI_PANEL_PORT, XUI_INBOUND_PORT, DOMAIN_NAME

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

## 🚀 Установка и проверка BBR

📦 **Автоматически** (если установлен 3x-ui):  
Открой `x-ui`, выбери **опцию 23** — установка BBR произойдёт автоматически.


🛠️ **Ручная установка**:

```bash
sudo modprobe tcp_bbr && echo 'tcp_bbr' | sudo tee -a /etc/modules-load.d/modules.conf && echo -e "net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr" | sudo tee /etc/sysctl.d/99-bbr.conf && sudo sysctl --system
```
## ✅ Проверка статуса BBR

Выполни по очереди команды. Ожидаемые результаты:
```bash
sysctl net.ipv4.tcp_congestion_control && sysctl net.core.default_qdisc && lsmod | grep bbr
```

| Команда                                | Описание                                      | Статус |
|----------------------------------------|-----------------------------------------------|--------|
| ``sysctl net.ipv4.tcp_congestion_control`` | → должен быть `bbr`                          | ✅      |
| ``sysctl net.core.default_qdisc``         | → должен быть `fq`                           | ✅      |
| ``lsmod \| grep bbr``                     | → должен вернуть строку типа: `tcp_bbr ...` | ✅      |

---

## 🔔 Установка Telegram-уведомлений

```bash
bash <(curl -Ls https://raw.githubusercontent.com/maxgalzer/secure-3xui-installer/main/install_notifier.sh)
```

- Скрипт создаёт `/root/renew_ssl.sh`
- Добавляет cron-задачу `22 4 * * *`
- Отправляет тестовое уведомление в Telegram

## 📬 Как получить Telegram Chat ID

1. Напиши любое сообщение своему боту в Telegram.  
2. Открой в браузере ссылку (замени `<TOKEN>` на токен своего бота):

   [`https://api.telegram.org/bot<TOKEN>/getUpdates`](https://api.telegram.org/bot<TOKEN>/getUpdates)


3. Найди в ответе блок:

   ```json
   "chat":{"id":902225799,"first_name":"NAME","username":"USERNAME","type":"private"}
4. Цифра после "id" — это и есть твой Telegram Chat ID.

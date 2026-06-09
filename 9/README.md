# Модуль 3, задание 9

## 1. HQ-SRV

Проверьте SSH-порт в `.env`:

```bash
SSH_PORT=2026
MAX_RETRY=3
BAN_TIME=60
```

Запустите:

```bash
chmod +x 01-hq-srv-fail2ban.sh
./01-hq-srv-fail2ban.sh
```

Проверка:

```bash
fail2ban-client status sshd
fail2ban-client get sshd maxretry
fail2ban-client get sshd bantime
```

## 2. Проверка с HQ-CLI

Три раза выполните команду и каждый раз введите неправильный пароль:

```bash
ssh \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  -o NumberOfPasswordPrompts=1 \
  -p 2026 \
  sshuser@192.168.1.10
```

После третьей неуспешной авторизации на HQ-SRV:

```bash
fail2ban-client status sshd
```

Адрес HQ-CLI должен появиться в `Banned IP list`. Через 60 секунд он будет
автоматически исключён из списка.

Ручная разблокировка:

```bash
fail2ban-client set sshd unbanip 192.168.2.10
```

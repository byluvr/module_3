# Импорт пользователей

На BR-SRV подключите `Additional.iso` и проверьте пути в `.env`.

```bash
chmod +x ./01-br-srv-import-users.sh
./01-br-srv-import-users.sh
```

## Проверка

```bash
samba-tool user list
```

Затем проверьте вход импортированного пользователя на HQ-CLI.

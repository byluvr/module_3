# Fail2ban для SSH

На HQ-SRV проверьте SSH-порт, число попыток и время блокировки в `.env`.

```bash
chmod +x ./01-hq-srv-fail2ban.sh
./01-hq-srv-fail2ban.sh
```

## Проверка

С HQ-CLI выполните три неудачных входа:

```bash
ssh -p 2026 sshuser@192.168.1.10
```

На HQ-SRV:

```bash
fail2ban-client status sshd
```

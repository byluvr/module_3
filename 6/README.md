# Модуль 3, задание 6

## 1. HQ-SRV

Проверьте размер ротации в `.env`:

```bash
ROTATE_SIZE=10M
```

Запустите:

```bash
chmod +x 01-hq-srv-rsyslog-server.sh
./01-hq-srv-rsyslog-server.sh
```

Скрипт использует уже установленный `crontab`. Отдельно устанавливать
пакет `cronie` на ALT Linux не требуется.

## 2. BR-SRV

```bash
chmod +x 02-br-srv-rsyslog-client.sh
./02-br-srv-rsyslog-client.sh
```

## 3. HQ-CLI: настройка маршрутизаторов

```bash
apt-get update
apt-get install -y expect openssh-clients sshpass

chmod +x 03-generate-router-configs.sh
chmod +x 04-apply-router-config.exp

./03-generate-router-configs.sh
./04-apply-router-config.exp all
```

## 4. Проверка на HQ-SRV

Подождите появления сообщений и выполните:

```bash
find /opt -maxdepth 2 -type f -ls
grep -R "AU-TEAM-RSYSLOG" /opt
```

Ожидаются отдельные каталоги:

```text
/opt/HQ-RTR/
/opt/BR-RTR/
/opt/BR-SRV/
```

Регистр имён зависит от фактического hostname устройств. Каталога HQ-SRV
в `/opt` быть не должно.

Проверка конфигурации и ротации:

```bash
rsyslogd -N1
logrotate -d /etc/logrotate.d/au-team-remote
cat /etc/cron.d/au-team-remote-logrotate
```

Для проверки ротации без ожидания 10 МБ:

```bash
logrotate -f /etc/logrotate.d/au-team-remote
find /opt -maxdepth 2 -type f -ls
```

## Диагностика BR-RTR

Проверьте каталог без учёта регистра:

```bash
find /opt -mindepth 1 -maxdepth 2 -print
find /opt -maxdepth 1 -type d -iname '*br*rtr*' -print
```

Убедитесь, что HQ-SRV слушает порт 514:

```bash
ss -lntup | grep ':514'
systemctl status rsyslog --no-pager
```

Посмотрите входящий трафик, затем вызовите событие на BR-RTR:

```bash
tcpdump -ni any port 514
```

В другом терминале несколько раз выполните неуспешный SSH-вход на BR-RTR:

```bash
ssh incorrect-user@172.16.5.5
```

После этого на HQ-SRV:

```bash
find /opt -maxdepth 2 -type f -ls
tail -n 30 /opt/*/messages.log
```

Проверка конфигурации BR-RTR:

```text
show running-config
```

В конфигурации должна присутствовать строка:

```text
rsyslog host 192.168.1.10 mode tcp port 514
```

Если `tcpdump` не видит пакетов, проверьте с BR-RTR доступность HQ-SRV:

```text
ping 192.168.1.10
```

Если пакеты видны, но файл не создаётся, проверьте ошибки rsyslog:

```bash
journalctl -u rsyslog -n 100 --no-pager
rsyslogd -N1
```

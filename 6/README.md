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

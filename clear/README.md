# Очистка после модуля 3

Скрипты удаляют только временные файлы автоматизации и локальную копию
`module_3`. Настроенные службы и результаты заданий сохраняются.

Не удаляются:

- shell history и системные журналы;
- сертификаты и ключи, используемые nginx;
- центр сертификации `/root/au-team-ca`;
- удалённые журналы в `/opt`;
- контейнеры, образы и Docker volumes мониторинга;
- отчёты `/etc/ansible/PC-INFO`;
- настройки fail2ban;
- PDF-файлы CUPS, включая `/raid/nfs/Print.pdf`;
- импортированные пользователи домена.

Перед запуском перейдите за пределы каталога `module_3`.

## HQ-CLI

```bash
cd /root
bash /root/module_3/clear/01-hq-cli-clean.sh
```

Удаляются только временная копия CA и текстовый файл тестовой печати.

## HQ-SRV

```bash
cd /root
bash /root/module_3/clear/02-hq-srv-clean.sh
```

Рабочие данные и тестовый PDF сохраняются.

## BR-SRV

```bash
cd /root
bash /root/module_3/clear/03-br-srv-clean.sh
```

Additional.iso отмонтируется от `/iso`, но запись задания в `/etc/fstab`
и импортированные пользователи сохраняются.

## ISP

```bash
cd /root
bash /root/module_3/clear/04-isp-clean.sh
```

Удаляются резервные копии автоматизации и дубликаты сертификатов из
`/home/sshuser`. Установленные файлы nginx сохраняются.

Для проверки без удаления проекта временно укажите в `.env`:

```bash
DELETE_PROJECT=no
```

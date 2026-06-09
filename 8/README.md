# Модуль 3, задание 8

На BR-SRV должен быть выполнен модуль 2, задание 5. Команда ниже должна
возвращать `pong` для HQ-SRV и HQ-CLI:

```bash
cd /etc/ansible
ansible -m ping HQ-SRV:HQ-CLI
```

Запуск инвентаризации:

```bash
chmod +x 01-br-srv-inventory.sh
./01-br-srv-inventory.sh
```

Скрипт создаёт:

```text
/etc/ansible/inventory.yml
/etc/ansible/PC-INFO/<hostname>.yml
```

Проверка:

```bash
ls -la /etc/ansible/PC-INFO
cat /etc/ansible/PC-INFO/*.yml
```

Каждый отчёт содержит имя компьютера и его основной IPv4-адрес.

# Отчёт: инвентаризация HQ-SRV и HQ-CLI

Инвентаризация выполняется с BR-SRV средствами Ansible.

Основные параметры:

- inventory: `/etc/ansible/hosts`;
- плейбук: `/etc/ansible/inventory.yml`;
- целевые машины: HQ-SRV и HQ-CLI;
- каталог отчётов: `/etc/ansible/PC-INFO`;
- формат отчётов: YAML;
- имя файла соответствует hostname инвентаризированной машины.

Каждый отчёт содержит:

```yaml
hostname: "имя компьютера"
ip_address: "основной IPv4-адрес"
```

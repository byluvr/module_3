# Модуль 3, задание 1: импорт пользователей

Скрипт запускается от `root` на контроллере домена `BR-SRV`.

## Параметры

При необходимости измените `.env`:

```bash
ISO_DEVICE=/dev/sr0
ISO_MOUNT=/iso
CSV_FILE=/iso/Users.csv
```

Регистр имени файла проверяется автоматически: подойдут `Users.csv` и
`users.csv`.

## Запуск

Подключите `Additional.iso` к `BR-SRV` и выполните:

```bash
bash 01-br-srv-import-users.sh
```

Скрипт:

1. Монтирует `/dev/sr0` в `/iso`.
2. Добавляет автомонтирование ISO в `/etc/fstab`.
3. Читает CSV с разделителем `;`.
4. Создаёт пользователей в формате `firstname.lastname`.
5. Устанавливает пароль из последнего столбца CSV.

Ожидаемый порядок столбцов:

```text
firstname;lastname;role;phone;ou;street;zip;city;country;password
```

## Проверка

На `BR-SRV`:

```bash
samba-tool user list
samba-tool user show firstname.lastname
```

На `HQ-CLI` завершите текущий сеанс и войдите под импортированным
пользователем домена:

```text
firstname.lastname
```

Используйте пароль из `Users.csv`.

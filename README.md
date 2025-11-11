<p align="center">
  <a href="https://stand-with-ukraine.pp.ua"><img src="https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg" alt="#StandWithUkraine" /></a>
</p>

[![Stand With Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/banner2-direct.svg)](https://vshymanskyy.github.io/StandWithUkraine/)

# Модуль PON Monitor (Ponmon)

Модуль моніторингу PON обладнання для білінгової системи [NoDeny Next](https://nodeny.com.ua/).

> [!CAUTION]
> Починаючи з ревізії 716 NoDeny Next (2025.09.11), даний модуль більше не входить в комплект поставки NoDeny Next, і розпосюджується окремо.
> З 2025.09.11 модуль можна встановлювати як на гілку NoDeny Next, так і на гілку NoDeny Next Plus, використовуючи версію модуля з v2025.09.01!

## Огляд

Ponmon - це комплексний модуль для моніторингу PON (Passive Optical Network) обладнання, разом з модулями вендорів OLT, які забезпечують:
- Моніторинг OLT та ONU
- Збір статистики потужності сигналу (RX/TX)
- Збір даних FDB для перегляду MAC-адрес за ONU
- Веб-інтерфейс для перегляду та управління обладнанням
- Автоматичне очищення застарілих даних в БД

## Модулі вендорів OLT

Модулі вендорів OLT купуються окремо в [кабінеті](https://app.nodeny-plus.com.ua/cgi-bin/stat.pl).
Наразі доступні модулі вендорів:
- ZTE
  - C220 (GPON/EPON)
  - C300 (GPON/EPON)
  - C320 (GPON/EPON)
  - C600 (GPON/EPON)
  - C610 (GPON/EPON)
  - C620 (GPON/EPON)
  - C650 (GPON/EPON)

- BDCOM
  - P3310B (EPON)
  - P3310C (EPON)
  - P3310D (EPON)
  - P3608B (EPON)
  - P3616-2TE (EPON)
  - GP3600-04 (GPON)
  - GP3600-08 (GPON)
  - GP3600-16B (GPON)

- STELS/C-DATA
  - серія FD11xx (EPON)
    - FD1104SN
    - FD1104SN-R1
    - FD1104SN-R1-DAP
    - FD1104SN-R2
    - FD1108S
    - FD1108SN
    - FD1108S-R1-DAP
  - серія FD12xx (EPON)
    - FD1204
    - FD1204SN-R1
    - FD1204SN-R2
    - FD1208S-R2-DAP
    - FD1216S-B1
  - серія FD16xx (GPON)
    - FD1616SN-R1
- V-Solutions
  - V1600D8 (EPON)

> [!IMPORTANT]
> Якщо вашої моделі немає в списку, але вона успішно моніториться модулем, будь ласка, зв'яжіться зі мною для додавання в список.

## Термінологія
- OLT (Optical Line Terminal) - це оптичний термінал, який забезпечує з'єднання через оптичне волокно до ONU.
- ONU (Optical Network Unit) - це оптичний мережевий пристрій, який забезпечує з'єднання через оптичне волокно до кінцевого користувача.
- FDB (Forwarding Database) - це база даних, яка містить інформацію про MAC-адреси за ONU.
- RX (Receive) - це сила сигналу прийому (dBm).
- TX (Transmit) - це сила сигналу передачі (dBm).
  

## Таблиці БД
Модуль використовує наступні таблиці:
- `pon_olt` - конфігурація OLT
- `pon_onu` - інформація про ONU
- `pon_bind` - прив'язки ONU до портів
- `pon_fdb` - FDB кеш
- `pon_mon` - тимчасові дані моніторингу
- `z{YYYY}_{MM}_{DD}_pon` - архівні дані по днях для графіків

## Встановлення

### Завантаження

Завантажити модуль вручну:
- з репозиторію [https://github.com/Mr-Method/Ponmon](https://github.com/Mr-Method/Ponmon)
- з [кабінету](https://app.nodeny-plus.com.ua/cgi-bin/stat.pl)

Завантажений архів розпакуйте в директорію `/usr/local/nodeny/modules/Ponmon`.

Завантажити модуль останньої версії з репозиторію через `git`: (рекомендовано)
```bash
cd /usr/local/nodeny/modules/
git clone https://github.com/Mr-Method/Ponmon ./Ponmon
```

Або можна завантажити версію по тегу з `git`: (для сумісності з старими модулями вендорів)
```bash
cd /usr/local/nodeny/modules/
git clone -b v2025.08.20_old https://github.com/Mr-Method/Ponmon ./Ponmon
```

### Залежності
```bash
# Встановлення Perl модулів
cd /usr/local/nodeny/modules/Ponmon/
cpanm --installdeps .
```

Потрібні модулі:
- Parallel::ForkManager >= 2.02
- Net::Telnet::Cisco >= 1.12
- Net::SNMP >= 6.0.1
- Net::SNMP::Util >= 1.04

### Інсталяція

```bash
# Встановлення Perl модулів
cd /usr/local/nodeny/
perl install.pl -x
perl install.pl -w=www
```

### Оновлення

> [!WARNING]  
> Після встановлення нової версії модуля, потрібно разово оновити структуру БД. Повторне запуск оновлення просто перевірить правильність структури БД.

Що буде змінено:
 - оновлення таблиці `pon_olt` для використання параметрів замість шаблонів
 - оновлення таблиці `pon_onu` для прив'язки до абонента або ТКД
 - оновлення таблиці `pon_bind` для запису дерева ONU
 - оновлення таблиці `pon_fdb`
 - конвертація таблиці параметрів з шаблонів на параметри

Перед оновленням:
 - зупинити модуль `ponmon` (якщо він запущений)
 - бажано зробити резервну копію таблиці `pon_olt`
 - запустити оновлення структури БД:
```bash
# Оновлення структури БД
perl /usr/local/nodeny/modules/Ponmon/bin/upgrade.pl
```

Після оновлення, можете переглянути налаштування через веб-інтерфейс:
 - `Налаштування -> Модулі -> PON-Monitor`
 - `Налаштування -> Ядро -> Моніторинг PON`
 - `Налаштування -> OLT Сервера`

## Запуск моніторингу
Модуль не рекомендується запускати як частина ядра NoDeny, бо він може завантажуватися дуже довго і впливати на роботу інших модулів.

Модуль бажано запускати як окремий процес:
```bash
cd /usr/local/nodeny/
# Запуск одноразово (для тестування)
perl nokrnel.pl -m=ponmon -vv

# Запуск в режимі демона
perl nokrnel.pl -m=ponmon -d &
```

> [!TIP]
> Починаючи з версії 2025.09.01 (виправлено в v2025.11.01), модуль можна запускати окремим процесом для кожногї OLT окремо, використовуючи команду `perl _noponmon.pl -o=1 -vv`. Для цього потрібно перемкнути запуск сканування OLT в режим "Самостійно", а в консолі виконати команду, наприклад для OLT з ID=1:
```bash
# Запуск одноразово (для тестування)
perl _noponmon.pl -o=1 -vv

# Запуск в режимі демона
perl _noponmon.pl -o=1 -d &
```

> [!NOTE]
> Для зручності керування процесами моніторингу OLT в режимі самостійного запуску, я використовую менеджер процесів `supervisor`.

Приклад конфігурації supervisor:
```bash
cat <<EOT > /etc/supervisor/conf.d/noponmon_1.conf
[program:noponmon_1]
environment=PATH="/usr/bin"
directory=/usr/local/nodeny/
command=perl _noponmon.pl -o=1 -d &
autostart=true
autorestart=true
startretries=3
#stderr_logfile=/var/log/nodeny/%(program_name)s.err.log
#stdout_logfile=/var/log/nodeny/%(program_name)s.out.log
EOT
```

Також можна об'єднати всі OLT в одну групу, для простішого керування:
```bash
cat <<EOT > /etc/supervisor/conf.d/_ponmon_group.conf
[group:pon_mon]
programs=noponmon_1, noponmon_2, noponmon_3, noponmon_4, noponmon_5
EOT
```

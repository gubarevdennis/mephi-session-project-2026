# Сессионный проект — Операционные системы семейства Unix — Денис Губарев

| Поле | Значение |
|---|---|
| Студент | Денис Губарев |
| Номер студента (в index.html) | 017 |
| ОС | Fedora 43 (aarch64) |
| Hostname | `mephi-2026.domain.local` |
| IP адрес | `192.168.1.100/24`, шлюз `192.168.1.1`, DNS `8.8.8.8` |
| Web-root | `/data/mephi-web/` |

## Как читать этот отчёт

По каждому пункту ТЗ указано: **какой командой выполнено**, **каким файлом подтверждается** и **статус**:

* ✅ — команда есть в истории (`project_history.txt` / `root_history`) и результат подтверждён файлом;
* ⚠️ — результат подтверждён файлом, но команда в сохранённой истории отсутствует. Объяснение причины и способ подтверждения даны в пункте;
* 🔧 — при выполнении была ошибка. Описано, что пошло не так и как исправлено.

**Почему в истории не хватает команд.** Начальная настройка ВМ (сеть, установка пакетов, разметка диска,
создание пользователя и группы) выполнялась под root в первой сессии. История этой сессии в
`/root/.bash_history` не сохранилась: после неё было несколько аварийных `reboot` из-за ошибок в PAM
(см. п. 5.1), а bash пишет историю в файл только при штатном выходе. Поэтому `root_history` начинается
уже с отладки PAM. Этого я не знал и не проверил историю до сдачи. Это моя ошибка.

Чтобы не подменять историю, недостающие пункты подтверждены **системными журналами**, которые нельзя
сфабриковать задним числом: `dnf history`, дата установки RPM, журнал аудита (`ausearch`), `blkid`, `systemctl is-enabled`.
Идемпотентные шаги ТЗ повторены скриптом [`fix_and_collect.sh`](fix_and_collect.sh). Полный протокол его
выполнения с выводом каждой команды лежит в `evidence/redo_log.txt`.

## Файлы проекта

| Файл | Раздел | Что подтверждает |
|---|---|---|
| `project_history.txt` | все | история команд пользователя `mephi-admin` |
| `root_history` | все | история команд root (`/root/.bash_history`) |
| `sudo_actions.txt` | 4, 5 | журнал sudo (`journalctl _COMM=sudo`) |
| `network_check.txt` | 1.2 | ping шлюза и 8.8.8.8 |
| `evidence/1.1_network_config.txt` | 1.1 | настройки nmcli, `ip addr`, `hostnamectl` |
| `evidence/2.1_dnf_history.txt`, `evidence/2.1_rpm_installtime.txt` | 2.1 | транзакции установки nginx, tcpdump, libcap-ng-utils |
| `tcpdump-4.99.6-2.fc43.aarch64.rpm`, `evidence/2.2_rpm_install.txt` | 2.2 | скачанный и установленный через rpm пакет |
| `evidence/3.1_lsblk_before.txt`, `evidence/3.1_blkid_after.txt`, `evidence/3.1_findmnt.txt` | 3.1 | раздел, ФС ext4, метка, монтирование |
| `fstab.txt` | 3.1 | запись автомонтирования |
| `nginx_recent_logs.txt`, `evidence/3.2_nginx_enabled.txt` | 3.2 | запуск и автозагрузка nginx |
| `users_groups.txt`, `evidence/4.1_audit_useradd.txt` | 4.1 | пользователь, группа, членство |
| `permissions.txt` | 4.1 | владелец и права `2775` |
| `selinux_status.txt`, `file_contexts.txt`, `evidence/4.2_semanage_local.txt` | 4.2 | Enforcing и контекст `httpd_sys_content_t` |
| `tcpdump_capabilities.txt`, `evidence/4.2_tcpdump_as_user.txt` | 4.2 | capabilities tcpdump |
| `index.html`, `curl_output.txt`, `evidence/5_final_check.txt`, `evidence/5_avc_nginx.txt` | 5.2 | ответ web-сервера при SELinux Enforcing |
| `mephi-nginx-screenshot.png` | 5.2 | скриншот сайта |
| `fix_and_collect.sh`, `evidence/redo_log.txt` | все | скрипт доработки и протокол его выполнения |

---

## Раздел 1. Управление сетью

### 1.1 Статический IP и hostname — ⚠️

Команда (в первой root-сессии, в историю не попала; повторена в `fix_and_collect.sh`):

```bash
nmcli connection modify <con> ipv4.method manual \
      ipv4.addresses 192.168.1.100/24 ipv4.gateway 192.168.1.1 ipv4.dns 8.8.8.8
nmcli connection up <con>
hostnamectl set-hostname mephi-2026.domain.local
```

В `root_history` есть проверка настроек: `nmcli connection show` (выполнялась 3 раза).
Hostname `mephi-2026.domain.local` виден в каждой строке `sudo_actions.txt` и `nginx_recent_logs.txt`.
Текущая конфигурация лежит в `evidence/1.1_network_config.txt`.

### 1.2 Проверка сети — ✅

```bash
ping -c 4 192.168.1.1 | tee network_check.txt
ping -c 4 8.8.8.8     | tee -a network_check.txt
```

Результат в `network_check.txt`: 0% packet loss для обоих адресов.

## Раздел 2. Управление программным обеспечением

### 2.1 Установка nginx, tcpdump, libcap-ng-utils — ⚠️

```bash
dnf install -y nginx tcpdump libcap-ng-utils
```

В истории этой команды нет (первая root-сессия). Факт и дата установки подтверждены журналом
транзакций dnf и базой RPM:

```bash
dnf history list --contains-pkgs=nginx      # и для tcpdump, libcap-ng-utils
rpm -q --qf '%{NAME} installed: %{INSTALLTIME:date}\n' nginx tcpdump libcap-ng-utils
```

Вывод лежит в `evidence/2.1_dnf_history.txt` и `evidence/2.1_rpm_installtime.txt`.
Косвенно установку подтверждают `nginx -t` и `getcap /usr/sbin/tcpdump` в `root_history`.
`getcap` входит в libcap, а `setcap`/`filecap` из libcap-ng-utils используются в п. 4.2.

### 2.2 Скачивание и установка RPM вручную — ✅ / 🔧

```bash
dnf download tcpdump                          # project_history.txt, строка 108
rpm -ivh --replacepkgs tcpdump-4.99.6-2.fc43.aarch64.rpm
```

`dnf download` есть в истории, файл `tcpdump-4.99.6-2.fc43.aarch64.rpm` лежит в репозитории.
**Проблема:** установку через `rpm` я тогда не выполнил: пакет уже стоял после п. 2.1, и я решил,
что повторная установка не нужна. Шаг повторён в `fix_and_collect.sh`. Ключ `--replacepkgs` нужен,
потому что пакет той же версии уже установлен. Вывод лежит в `evidence/2.2_rpm_install.txt`.

## Раздел 3. Файловые системы и сервисы

### 3.1 Разметка диска, ФС с меткой, автомонтирование — ⚠️ / 🔧

Разметка и форматирование (первая root-сессия, в историю не попали):

```bash
parted /dev/<disk> --script mklabel gpt mkpart primary ext4 0% 100%
mkfs.ext4 /dev/<disk>1
mkdir -p /data/mephi-web
```

**Проблема:** раздел был отформатирован **без метки**, а в `/etc/fstab` записан по UUID
(`UUID=772beb11-…`, см. старую версию `fstab.txt` в истории git). Исправлено без потери данных:
метка выставлена утилитой `e2label`, и fstab переведён на метку:

```bash
e2label /dev/<disk>1 MEPHI_DATA
sed -i 's#^UUID=772beb11-14e2-45c7-a66e-757ab4ec675d#LABEL=MEPHI_DATA#' /etc/fstab
systemctl daemon-reload
umount /data/mephi-web && mount -a
findmnt /data/mephi-web
```

Запись в `fstab.txt`:

```
LABEL=MEPHI_DATA /data/mephi-web ext4 defaults,nofail 0 2
```

Редактирование fstab видно в `root_history` (`nano /etc/fstab`, 2 раза), после каждого был `reboot`
для проверки автомонтирования. Подтверждение лежит в `evidence/3.1_*.txt`. Номер раздела ext4 виден
в выводе `stat` в `permissions.txt` (`Inode: 2`, корень отдельной ФС).

### 3.2 Запуск nginx и автозагрузка — ✅ / ⚠️

```bash
nano /etc/nginx/nginx.conf          # root /data/mephi-web;   (root_history)
nginx -t                            # root_history
systemctl restart nginx             # root_history
systemctl enable --now nginx        # первая сессия; повторено в fix_and_collect.sh
systemctl is-enabled nginx          # -> enabled
journalctl -u nginx --no-pager -n 30 > nginx_recent_logs.txt
```

В `nginx_recent_logs.txt` видно: `configuration file ... test is successful`, `Started nginx.service`.
Автозагрузка подтверждена в `evidence/3.2_nginx_enabled.txt`. Директива `root` лежит в `evidence/3.2_nginx_root.txt`.

## Раздел 4. Управление доступом

### 4.1 Пользователь, группа, права — ⚠️ / ✅

```bash
useradd -m -s /bin/bash mephi-admin     # первая сессия
groupadd mephi-devs                     # первая сессия
usermod -aG mephi-devs mephi-admin      # первая сессия; повторено (идемпотентно)
chown mephi-admin:mephi-devs /data/mephi-web/   # root_history ✅
chmod 2775 /data/mephi-web/                      # root_history ✅
```

`useradd`/`groupadd` повторить нельзя: объекты уже существуют. Факт их выполнения подтверждён
журналом аудита (`ausearch -m ADD_USER,ADD_GROUP,USER_MGMT,GRP_MGMT -i`, а также `/var/log/secure`
и `journalctl`) в `evidence/4.1_audit_useradd.txt`.

Результат:

* `users_groups.txt`: `uid=1000(mephi-admin) … groups=1000(mephi-admin),1001(mephi-devs)`;
* `permissions.txt`: `Access: (2775/drwxrwsr-x) Uid: mephi-admin Gid: mephi-devs`.

### 4.2 SELinux и capabilities — 🔧

**Что было сделано изначально (root_history):**

```bash
getenforce                                          # Enforcing
chcon -Rv --type=httpd_sys_content_t /data/mephi-web/
restorecon -Rv /data/mephi-web/
...
chcon -t httpd_sys_content_t /data/mephi-web/index.html
setsebool -P httpd_enable_homedirs on
```

**В чём была ошибка.** `chcon` меняет контекст временно, без записи в политику. Следующий за ним
`restorecon` вернул контекст по политике, а в политике для `/data/...` правила не было. Поэтому
директория снова получила `default_t` (`file_contexts.txt`). В `stat` на смонтированной ФС виден
`unlabeled_t` (`permissions.txt`). Потом я поменял контекст через `chcon` только у `index.html`,
а у самой директории он остался неверным. `setsebool httpd_enable_homedirs` к задаче отношения
не имеет, это была ошибочная попытка исправления. Преподаватель прав: с такими контекстами nginx
при Enforcing не должен отдавать страницу. Сохранённые мной файлы противоречат скриншоту,
и объяснить это по имеющимся данным я не могу. Поэтому SELinux исправлен правильно,
а работа сайта перепроверена при Enforcing с проверкой AVC-отказов (см. п. 5.2).

**Правильное исправление (постоянное правило в политике):**

```bash
semanage fcontext -a -t httpd_sys_content_t "/data/mephi-web(/.*)?"
restorecon -Rv /data/mephi-web
semanage fcontext -l -C                 # правило есть в локальной политике
ls -Zd /data/mephi-web                  # -> httpd_sys_content_t
ls -Z  /data/mephi-web/index.html       # -> httpd_sys_content_t
```

Результат лежит в `file_contexts.txt` и `evidence/4.2_semanage_local.txt`, статус в `selinux_status.txt`.

**Capabilities для tcpdump:**

```bash
chmod u-s /usr/sbin/tcpdump
setcap cap_net_raw,cap_net_admin+ep /usr/sbin/tcpdump
getcap /usr/sbin/tcpdump     # root_history ✅
```

Результат лежит в `tcpdump_capabilities.txt`: `/usr/sbin/tcpdump cap_net_admin,cap_net_raw=ep`.
**Проблема:** сам `setcap` в историю не попал. В `root_history` есть только проверка `getcap`.
Команда повторена в `fix_and_collect.sh`. Захват трафика от обычного пользователя без sudo
проверен (`su - mephi-admin -c 'tcpdump -c 3 -i any'`), результат лежит в `evidence/4.2_tcpdump_as_user.txt`.

## Раздел 5. Аутентификация и тестирование

### 5.1 Запрет входа root через PAM — 🔧

```bash
echo root > /etc/security/denied_users
chmod 644 /etc/security/denied_users            # root_history
restorecon -v /etc/security/denied_users        # root_history
nano /etc/pam.d/sshd                            # root_history
nano /etc/pam.d/system-auth                     # root_history
# добавлена строка:
# auth required pam_listfile.so onerr=succeed item=user sense=deny file=/etc/security/denied_users
```

**Проблема:** сначала я вписал строку в `/etc/pam.d/system-auth` с ошибкой в синтаксисе.
Из-за этого сломался `sudo`: в `sudo_actions.txt` видны ошибки `PAM (sudo) illegal module type: item=user`,
`no control flag supplied`, `PAM account management error`. Поскольку `system-auth` подключается всеми
сервисами, ошибка ломала вход везде, и пришлось несколько раз перезагружаться (отсюда множество
`reboot` в `root_history` и потеря ранней истории). Исправление: строка оставлена только в
`/etc/pam.d/sshd` в корректном виде и убрана из `system-auth`. После этого `sudo whoami`
работает (`sudo_actions.txt`, 15:20:12).

### 5.2 Web-страница и проверка — ✅

```bash
echo "Hello from Student: 017" | sudo tee /data/mephi-web/index.html
curl http://localhost | sudo tee /mifi-unix-project/curl_output.txt     # project_history.txt, строка 22
```

**Проблема по ходу:** `sudo echo ... > файл` не работает, потому что перенаправление выполняет
оболочка обычного пользователя, а не sudo (строки 4–5 истории). Правильный вариант — `| sudo tee`.
Также `mephi-admin` сначала не был в sudoers (`user NOT in sudoers` в `sudo_actions.txt`).
Исправлено добавлением в группу `wheel` (`usermod -aG wheel mephi-admin`).

Итоговая проверка при SELinux Enforcing после исправления п. 4.2 (`evidence/5_final_check.txt`):

```bash
getenforce                        # Enforcing
curl http://localhost             # Hello from Student: 017
curl http://192.168.1.100         # Hello from Student: 017
ausearch -m AVC -c nginx -ts recent   # отказов нет -> evidence/5_avc_nginx.txt
```

Скриншот лежит в `mephi-nginx-screenshot.png`.

---

## Итог: что было сделано некорректно и как исправлено

| # | Проблема | Исправление |
|---|---|---|
| 1 | История первой root-сессии потеряна из-за аварийных перезагрузок | Подтверждение через `dnf history`, `rpm`, `ausearch`, `blkid`; идемпотентные шаги повторены скриптом |
| 2 | Не выполнена установка RPM через `rpm` | `rpm -ivh --replacepkgs` |
| 3 | ФС без метки, fstab по UUID | `e2label … MEPHI_DATA`, fstab переведён на `LABEL=` |
| 4 | SELinux: `chcon` вместо `semanage`, `restorecon` откатил контекст | `semanage fcontext -a` + `restorecon -Rv` |
| 5 | `setcap` не попал в историю | повторён, проверен запуск tcpdump от `mephi-admin` |
| 6 | Ошибка в `system-auth` сломала sudo | строка pam_listfile перенесена в `/etc/pam.d/sshd` |
| 7 | Не было README с пояснениями | этот отчёт |

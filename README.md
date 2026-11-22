# Сессионный проект — Операционные системы семейства Unix — Денис Губарев

| Поле | Значение |
|---|---|
| Студент | Денис Губарев |
| Номер студента | 017 |
| ОС | Fedora 43 (aarch64) |
| Hostname | `mephi-2026.domain.local` |
| IP адрес | `192.168.1.100/24`, шлюз `192.168.1.1`, DNS `8.8.8.8` |
| Web-root | `/data/mephi-web/` (отдельный диск, ext4, метка `MEPHI_DATA`) |

## Почему проект выполнен повторно

Первую версию проекта преподаватель проверил и нашёл в ней ошибки. Разбор ошибок дан в конце README.
Главные из них:

* история первой root-сессии (сеть, пакеты, диск, пользователи) не сохранилась;
* SELinux-контекст был выставлен через `chcon`, а следующий `restorecon` его откатил, так что директория осталась `default_t`;
* ФС была создана без метки;
* не выполнены `rpm -i` и `setcap`.

Поэтому все пункты ТЗ выполнены **заново, с нуля**, скриптом [`project_setup.sh`](project_setup.sh).
Скрипт включает запись истории bash (`set -o history`), поэтому каждая реально выполненная команда
с датой и временем попадает в `project_history.txt`. Плюс `set -x` печатает каждую команду
вместе с подставленными значениями.

Запуск:

```bash
lsblk                                         # найти отдельный диск под web-данные
sudo DISK=/dev/nvme0n2 bash project_setup.sh  # подтвердить вводом YES
```

## Файлы проекта

| Файл | Раздел | Что проверяется |
|---|---|---|
| `project_setup.sh` | все | все команды выполнения ТЗ |
| `project_history.txt` | все | история реально выполненных команд (с датой/временем) |
| `network_check.txt` | 1.2 | ping шлюза и 8.8.8.8 |
| `tcpdump-4.99.6-2.fc43.aarch64.rpm` | 2.2 | RPM, скачанный через `dnf download` |
| `fstab.txt` | 3.1 | запись автомонтирования по метке |
| `nginx_recent_logs.txt` | 3.2 | журнал запуска nginx |
| `users_groups.txt` | 4.1 | пользователь `mephi-admin`, группа `mephi-devs` |
| `permissions.txt` | 4.1 | `stat` директории: `2775`, `mephi-admin:mephi-devs` |
| `selinux_status.txt` | 4.2 | `Enforcing` |
| `file_contexts.txt` | 4.2 | контекст `httpd_sys_content_t` у директории и `index.html` |
| `tcpdump_capabilities.txt` | 4.2 | `cap_net_admin,cap_net_raw=ep` |
| `index.html`, `curl_output.txt` | 5.2 | страница и ответ web-сервера |
| `mephi-nginx-screenshot.png` | 5.2 | скриншот сайта в браузере |

Старые файлы первой попытки (`root_history`, `sudo_actions.txt`) оставлены для истории. Разбор ошибок по ним дан ниже.

---

## Раздел 1. Управление сетью

### 1.1 Статический IP и hostname

```bash
nmcli connection modify "<con>" ipv4.method manual ipv4.addresses 192.168.1.100/24 \
      ipv4.gateway 192.168.1.1 ipv4.dns 8.8.8.8
nmcli connection up "<con>"
hostnamectl set-hostname mephi-2026.domain.local
```

Имя активного ethernet-подключения скрипт определяет сам: `nmcli -g NAME,TYPE connection show --active`.
Проверка: `nmcli connection show "<con>" | grep ipv4.` и `ip -4 addr show`.

### 1.2 Проверка сети

```bash
ping -c 4 192.168.1.1 | tee network_check.txt
ping -c 4 8.8.8.8     | tee -a network_check.txt
```

Результат лежит в `network_check.txt`, ожидается `0% packet loss` для обоих адресов.

## Раздел 2. Управление программным обеспечением

### 2.1 Установка пакетов

```bash
dnf install -y nginx tcpdump libcap-ng-utils policycoreutils-python-utils parted
```

`policycoreutils-python-utils` нужен для `semanage`, `parted` нужен для разметки диска.

### 2.2 Скачивание и ручная установка RPM

```bash
dnf download tcpdump
rpm -ivh --replacepkgs tcpdump-*.rpm
rpm -qi tcpdump
```

`--replacepkgs` нужен, потому что пакет той же версии уже установлен в п. 2.1.

## Раздел 3. Файловые системы и сервисы

### 3.1 Разметка, ФС с меткой, автомонтирование

```bash
wipefs -a /dev/nvme0n2
parted /dev/nvme0n2 --script mklabel gpt mkpart primary ext4 0% 100%
mkfs.ext4 -F -L MEPHI_DATA /dev/nvme0n2p1
mkdir -p /data/mephi-web
echo "LABEL=MEPHI_DATA  /data/mephi-web  ext4  defaults  0 2" >> /etc/fstab
systemctl daemon-reload
mount -a
findmnt /data/mephi-web
lsblk -f /dev/nvme0n2
cp /etc/fstab fstab.txt
```

Монтирование идёт по метке, а не по UUID или имени устройства. Поэтому запись в fstab не зависит
от того, под каким именем ядро увидит диск.

### 3.2 nginx: запуск и автозагрузка

```bash
sed -i 's#root .*;#root /data/mephi-web;#' /etc/nginx/nginx.conf   # первый root в server{}
nginx -t
systemctl enable --now nginx
systemctl is-enabled nginx        # enabled
systemctl is-active nginx         # active
firewall-cmd --permanent --add-service=http && firewall-cmd --reload
journalctl -u nginx --no-pager -n 30 | tee nginx_recent_logs.txt
```

## Раздел 4. Управление доступом

### 4.1 Пользователь, группа, права

```bash
useradd -m -s /bin/bash mephi-admin
groupadd mephi-devs
usermod -aG mephi-devs mephi-admin
usermod -aG wheel mephi-admin          # права sudo
chown mephi-admin:mephi-devs /data/mephi-web
chmod 2775 /data/mephi-web
id mephi-admin; getent group mephi-devs   > users_groups.txt
stat /data/mephi-web                      > permissions.txt
```

`2775` означает `rwxrwsr-x`. Бит SGID (`2`) нужен, чтобы новые файлы в директории наследовали
группу `mephi-devs`.

### 4.2 SELinux и capabilities

```bash
setenforce 1                       # и SELINUX=enforcing в /etc/selinux/config
semanage fcontext -a -t httpd_sys_content_t "/data/mephi-web(/.*)?"
restorecon -Rv /data/mephi-web
getenforce                 > selinux_status.txt
ls -Zd /data/mephi-web     > file_contexts.txt
ls -Z /data/mephi-web/index.html >> file_contexts.txt
```

`semanage fcontext` записывает правило в политику, поэтому контекст переживает `restorecon`
и перемаркировку ФС. В первой попытке я использовал `chcon`, который правило не записывает (см. разбор ниже).

```bash
chmod u-s /usr/sbin/tcpdump
setcap cap_net_raw,cap_net_admin+ep /usr/sbin/tcpdump
getcap /usr/sbin/tcpdump  > tcpdump_capabilities.txt
filecap /usr/sbin/tcpdump                          # из libcap-ng-utils
su - mephi-admin -c 'timeout 5 tcpdump -c 3 -i any -nn'   # захват без sudo
```

## Раздел 5. Аутентификация и тестирование

### 5.1 Запрет входа root по SSH

```bash
echo root > /etc/security/denied_users
chmod 644 /etc/security/denied_users
restorecon -v /etc/security/denied_users
# вторая строка /etc/pam.d/sshd:
# auth required pam_listfile.so onerr=succeed item=user sense=deny file=/etc/security/denied_users
echo 'PermitRootLogin no' > /etc/ssh/sshd_config.d/10-deny-root.conf
sshd -t && systemctl restart sshd
```

Строка добавлена **только** в `/etc/pam.d/sshd`. В первой попытке я вписал её с ошибкой в
`system-auth`, и это сломало `sudo` (см. разбор).

### 5.2 Web-страница и проверка

```bash
echo "Hello from Student: 017" > /data/mephi-web/index.html
restorecon -Rv /data/mephi-web
curl -s http://localhost | tee curl_output.txt     # Hello from Student: 017
curl -s http://192.168.1.100
ausearch -m AVC -c nginx -ts today                 # отказов SELinux для nginx нет
```

Проверка проходит при SELinux **Enforcing**, без отключения SELinux и без лишних `setsebool`.
Скриншот лежит в `mephi-nginx-screenshot.png`.

---

## Разбор ошибок первой попытки

| # | Ошибка (по `root_history`, `project_history` старой версии, `sudo_actions.txt`) | Причина | Как сделано теперь |
|---|---|---|---|
| 1 | В истории нет настройки сети, установки пакетов, разметки диска, `useradd` | история первой root-сессии не сохранилась, а я не проверил её до сдачи | скрипт с `set -o history`, история пишется в `project_history.txt` |
| 2 | `/data/mephi-web` с контекстом `default_t` / `unlabeled_t` | `chcon -R` → `restorecon -R` откатил контекст, правила в политике не было; потом `chcon` применён только к `index.html` | `semanage fcontext -a` + `restorecon -Rv` |
| 3 | `setsebool -P httpd_enable_homedirs on` | ошибочная попытка: этот флаг для `~/public_html`, к `/data` отношения не имеет | не используется |
| 4 | ФС без метки, fstab по UUID | при форматировании не указал `-L` | `mkfs.ext4 -L MEPHI_DATA`, `LABEL=` в fstab |
| 5 | Нет `rpm -i`, нет `setcap`, нет `systemctl enable` | пропустил шаги ТЗ | выполнены в скрипте |
| 6 | `PAM (sudo) illegal module type: item=user` в `sudo_actions.txt` | ошибка синтаксиса строки `pam_listfile` в `/etc/pam.d/system-auth`, которую подключают все сервисы | строка только в `/etc/pam.d/sshd` в правильном формате, проверка `sshd -t` |
| 7 | `sudo echo ... > файл` не записывал файл | перенаправление выполняет оболочка пользователя, а не sudo | запись от root / через `\| sudo tee` |
| 8 | `user NOT in sudoers` | `mephi-admin` не был в `wheel` | `usermod -aG wheel mephi-admin` |

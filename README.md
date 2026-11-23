# Сессионный проект — Операционные системы семейства Unix - Денис Губарев

| | |
|---|---|
| **Студент** | Денис Губарев |
| **Зачётная книжка** | ________ |
| **ОС** | Fedora 43 |
| **Hostname** | `mephi-2026.domain.local` |
| **IP адрес** | `192.168.1.100/24` |

---

## Файлы проекта

| Файл | Раздел | Что проверяется |
|---|---|---|
| `project_history.txt` | все | история выполненных команд |
| `project_setup.sh` | все | все команды выполнения ТЗ одним скриптом |
| `network_check.txt` | 1.2 | ping шлюза `192.168.1.1` и `8.8.8.8` |
| `tcpdump-4.99.6-2.fc43.*.rpm` | 2.2 | RPM, скачанный через `dnf download` |
| `fstab.txt` | 3.1 | автомонтирование `/data/mephi-web` по метке `MEPHI_DATA` |
| `nginx_recent_logs.txt` | 3.2 | журнал запуска nginx |
| `users_groups.txt` | 4.1 | пользователь `mephi-admin`, группа `mephi-devs` |
| `permissions.txt` | 4.1 | владелец `mephi-admin:mephi-devs`, права `2775` |
| `selinux_status.txt` | 4.2 | SELinux в режиме `Enforcing` |
| `file_contexts.txt` | 4.2 | контекст `httpd_sys_content_t` |
| `tcpdump_capabilities.txt` | 4.2 | `cap_net_admin,cap_net_raw=ep` |
| `index.html` | 5.2 | страница сайта |
| `curl_output.txt` | 5.2 | ответ web-сервера по `http://192.168.1.100` |
| `mephi-nginx-screenshot.png` | 5.2 | скриншот работающего сайта |

---

## Краткий отчёт по разделам

### Раздел 1 — Управление сетью

**1.1 Настройка сети.** Статический IP `192.168.1.100/24`, шлюз `192.168.1.1`, DNS `8.8.8.8`, hostname `mephi-2026.domain.local`.

```bash
nmcli connection modify "<подключение>" ipv4.method manual \
    ipv4.addresses 192.168.1.100/24 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns 8.8.8.8
nmcli connection up "<подключение>"
hostnamectl set-hostname mephi-2026.domain.local
```

**1.2 Проверка сети.** Маршрут по умолчанию ведёт на `192.168.1.1`, есть связь со шлюзом и с внешним миром.
Результат лежит в `network_check.txt` (копия в `/tmp/network_check.txt`): 0% потерь пакетов.

```bash
ip route show default            # default via 192.168.1.1
ping -c 4 192.168.1.1 >  network_check.txt
ping -c 4 8.8.8.8     >> network_check.txt
```

### Раздел 2 — Управление программным обеспечением

**2.1 Установка пакетов** `nginx`, `tcpdump`, `libcap-ng-utils` из репозитория:

```bash
dnf install -y nginx tcpdump libcap-ng-utils
dnf install -y policycoreutils-python-utils parted wget lynx   # semanage, parted, проверка сайта
```

**2.2 Ручная установка RPM.** Пакет `tcpdump` скачан в `/tmp` через `dnf download` и установлен командой `rpm`, файл пакета лежит в репозитории:

```bash
dnf download --destdir=/tmp tcpdump
rpm -ivh --replacepkgs /tmp/tcpdump-4.99.6-2.fc43.*.rpm
```

### Раздел 3 — Файловые системы и сервисы

**3.1 Отдельный диск под web-данные.** На втором диске создан один раздел на всё пространство, отформатирован в ext4
с меткой `MEPHI_DATA` и смонтирован в `/data/mephi-web`. Автомонтирование при загрузке настроено по метке в `/etc/fstab`,
запись лежит в `fstab.txt`.

```bash
parted /dev/<диск> --script mklabel gpt mkpart primary ext4 0% 100%
mkfs.ext4 -L MEPHI_DATA /dev/<диск>1
mkdir -p /data/mephi-web
echo "LABEL=MEPHI_DATA  /data/mephi-web  ext4  defaults  0 2" >> /etc/fstab
systemctl daemon-reload
mount -a
```

**3.2 Nginx.** В `/etc/nginx/nginx.conf` web-root указан как `root /data/mephi-web;`, сервис запущен
и добавлен в автозагрузку. Сообщения журнала nginx за последние 5 минут лежат в `nginx_recent_logs.txt`
(копия в `/tmp/nginx_recent_logs.txt`).

```bash
sed -i 's#root .*;#root /data/mephi-web;#' /etc/nginx/nginx.conf
nginx -t
systemctl start nginx
systemctl enable nginx
journalctl -u nginx --since "5 minutes ago" > nginx_recent_logs.txt
```

### Раздел 4 — Управление доступом

**4.1 Пользователь, группа, права.** Создан пользователь `mephi-admin` с паролем из ТЗ и группа `mephi-devs`,
пользователь добавлен в группу. Директории `/data/mephi-web` назначены владелец `mephi-admin:mephi-devs` и права `2775`
(SGID: новые файлы наследуют группу). Результаты лежат в `users_groups.txt` и `permissions.txt`.

```bash
useradd -m -s /bin/bash mephi-admin
groupadd mephi-devs
echo "mephi-admin:P@ssw0rd2026" | chpasswd
usermod -aG mephi-devs mephi-admin
chown mephi-admin:mephi-devs /data/mephi-web
chmod 2775 /data/mephi-web
```

**4.2 SELinux и capabilities.** SELinux работает в режиме `Enforcing`. Для `/data/mephi-web` в политику добавлен
контекст `httpd_sys_content_t`. У `tcpdump` снят SUID и выставлены capabilities, поэтому обычный пользователь
`mephi-admin` запускает его без ошибок доступа. Результаты лежат в `selinux_status.txt`, `file_contexts.txt` и `tcpdump_capabilities.txt`.

```bash
semanage fcontext -a -t httpd_sys_content_t "/data/mephi-web(/.*)?"
restorecon -Rv /data/mephi-web
chmod u-s /usr/sbin/tcpdump
setcap cap_net_raw,cap_net_admin+ep /usr/sbin/tcpdump
getcap /usr/sbin/tcpdump
sudo -u mephi-admin tcpdump --help
```

### Раздел 5 — Аутентификация и тестирование

**5.1 Запрет входа root.** Пользователь root не может войти ни с локальной консоли, ни по SSH. Сделано через
PAM (`pam_listfile.so`) в `login` и `sshd`, плюс директива `PermitRootLogin no`. Остальные пользователи входят как обычно.

```bash
echo "root" > /etc/ssh/denied_users
# в /etc/pam.d/login и /etc/pam.d/sshd добавлена строка:
# auth required pam_listfile.so onerr=succeed item=user sense=deny file=/etc/ssh/denied_users
echo 'PermitRootLogin no' > /etc/ssh/sshd_config.d/10-deny-root.conf
systemctl restart sshd
```

**5.2 Web-страница и проверка.** Страница `index.html` создана от имени `mephi-admin`. Благодаря SGID она
получила группу `mephi-devs`. Сервер отвечает на `localhost` и по `http://192.168.1.100` при SELinux `Enforcing`.
Ответ лежит в `curl_output.txt`.

```bash
sudo -u mephi-admin bash -c "echo 'Hello from Student: 017' > /data/mephi-web/index.html"
curl http://localhost
curl -s http://192.168.1.100 > curl_output.txt
wget -qO- http://192.168.1.100
lynx -dump http://192.168.1.100
```

Вывод:

```
Hello from Student: 017
```

---

## Скриншоты

* `mephi-nginx-screenshot.png`: сайт открыт в браузере по `http://192.168.1.100`.

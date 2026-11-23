# Тестовый прогон `project_setup.sh` в QEMU

**Это не результаты сдачи.** Файлы получены при проверке скрипта `project_setup.sh` на тестовой виртуальной машине,
которую Claude (ИИ-ассистент) развернул в облачном контейнере. Скрипт запускался без участия студента.

| Параметр | Тестовая ВМ |
|---|---|
| Образ | Fedora 43 Cloud Base, x86_64 |
| Виртуализация | QEMU, программная эмуляция (TCG) |
| SELinux | Enforcing |
| Сеть | user-mode QEMU: IP `10.0.2.15/24`, шлюз `10.0.2.2`, DNS `10.0.2.3`. В ТЗ `192.168.1.100`, `192.168.1.1`, `8.8.8.8`: в тестовой сети этих адресов нет |
| Второй диск | `/dev/vdb`, 2 ГБ (в ТЗ `/dev/sdb`) |

Запуск:

```bash
echo YES | sudo DISK=/dev/vdb IP=10.0.2.15/24 GW=10.0.2.2 DNS=10.0.2.3 bash project_setup.sh > run.log 2>&1
```

Код выхода — 0. В `run.log` лежит полный вывод скрипта с трассировкой (`set -x`), в `project_history.txt` — история команд.
`mephi-nginx-screenshot.png` снят браузером Chromium (Playwright) со страницы, которую отдаёт nginx тестовой ВМ.

## Сверка файлов с ТЗ (раздел 6.1)

| Файл | Команда по ТЗ | Результат |
|---|---|---|
| `project_history.txt` | `history` | все команды разделов 1–5 |
| `network_check.txt` | `ping -c 4 <шлюз>`, `ping -c 4 <внешний адрес>` | 0% потерь в обоих случаях |
| `nginx_recent_logs.txt` | `journalctl -u nginx --since "5 minutes ago"` | запуск nginx, проверка конфигурации |
| `fstab.txt` | `cp /etc/fstab` | `LABEL=MEPHI_DATA  /data/mephi-web  ext4  defaults  0 2` |
| `selinux_status.txt` | `getenforce` | `Enforcing` |
| `file_contexts.txt` | `ls -Zd /data/mephi-web` | `system_u:object_r:httpd_sys_content_t:s0 /data/mephi-web` |
| `tcpdump_capabilities.txt` | `getcap /usr/sbin/tcpdump` | `/usr/sbin/tcpdump cap_net_admin,cap_net_raw=ep` |
| `permissions.txt` | `stat /data/mephi-web` | `2775/drwxrwsr-x`, `mephi-admin`/`mephi-devs`, `httpd_sys_content_t` |
| `users_groups.txt` | `id mephi-admin`, `getent group mephi-devs` | `mephi-admin` состоит в `mephi-devs` |
| `index.html` | создан от имени `mephi-admin` | `Hello from Student: 017` |
| `curl_output.txt` | `curl -s http://<IP>` | `Hello from Student: 017` |
| `mephi-nginx-screenshot.png` | скриншот | страница в браузере |
| `tcpdump-*.rpm` | `dnf download --destdir=/tmp tcpdump` | пакет tcpdump 4.99.6 |

## Дополнительно проверено на этой ВМ

* `sudo -u mephi-admin tcpdump --help` выполняется без ошибок доступа;
* `index.html`, созданный `mephi-admin`, получил группу `mephi-devs` (SGID);
* вход root по SSH отклоняется;
* после перезагрузки сохраняются: монтирование по метке, автозапуск nginx, контекст SELinux, capabilities;
* повторный запуск на уже настроенной системе проходит без ошибок.

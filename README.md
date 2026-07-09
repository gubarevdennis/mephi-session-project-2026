# Сессионный проект — ОС Unix

Студент: Денис Губарев
ОС: Fedora 43
Hostname: `mephi-2026.domain.local`
Web-root: `/data/mephi-web/`
Содержимое сайта: `Hello from Student: 017`

## Важное пояснение

После повторной проверки обнаружена проблема с фиксацией SELinux-контекста. В отправленных файлах:

* `selinux_status.txt` показывает `Enforcing`;
* `file_contexts.txt` показывает для `/data/mephi-web/` контекст `default_t`;
* `permissions.txt` показывает контекст `unlabeled_t`.

Это означает, что в момент выгрузки отчётных файлов SELinux-контекст директории был зафиксирован некорректно, и при строгой проверке nginx/httpd не должен был получать доступ к содержимому директории. Работоспособность сайта была подтверждена через `curl_output.txt` и скриншот, но SELinux-настройка была оформлена неполно.

Корректный вариант исправления:

```bash
sudo semanage fcontext -a -t httpd_sys_content_t "/data/mephi-web(/.*)?"
sudo restorecon -Rv /data/mephi-web
ls -Zd /data/mephi-web
ls -Z /data/mephi-web/index.html
getenforce
curl http://localhost
```

Результат вывода:

```bash
Enforcing
system_u:object_r:httpd_sys_content_t:s0 /data/mephi-web
Hello from Student: 017
```

## Файлы проекта

| Файл                         | Что подтверждает                                    |
| ---------------------------- | --------------------------------------------------- |
| `project_history.txt`        | История команд пользователя                         |
| `root_history`               | Дополнительная история команд root                  |
| `network_check.txt`          | Проверка сети                                       |
| `fstab.txt`                  | Монтирование `/data/mephi-web`                      |
| `users_groups.txt`           | Пользователь `mephi-admin` и группа `mephi-devs`    |
| `permissions.txt`            | Права `2775`, владелец `mephi-admin:mephi-devs`     |
| `selinux_status.txt`         | SELinux в режиме `Enforcing`                        |
| `file_contexts.txt`          | SELinux-контекст директории, зафиксирован с ошибкой |
| `tcpdump_capabilities.txt`   | Capabilities для `tcpdump`                          |
| `nginx_recent_logs.txt`      | Успешный запуск nginx                               |
| `curl_output.txt`            | Ответ web-сервера                                   |
| `index.html`                 | HTML-файл сайта                                     |
| `mephi-nginx-screenshot.png` | Скриншот работающего сайта                          |

## 1. Сеть

Была проверена связность до шлюза и внешнего DNS.

```bash
ping 192.168.1.1
ping 8.8.8.8
```

Результат сохранён в `network_check.txt`: потери пакетов 0%.

## 2. Пользователи и группы

Создан пользователь `mephi-admin`, создана группа `mephi-devs`, пользователь добавлен в группу.

Проверка:

```bash
id mephi-admin
getent group mephi-devs
```

Результат сохранён в `users_groups.txt`.

## 3. Файловая система и автомонтирование

Для web-директории использовалась точка монтирования:

```bash
/data/mephi-web
```

Запись сохранена в `fstab.txt`.

В текущем варианте использована запись по UUID:

```bash
UUID=772beb11-14e2-45c7-a66e-757ab4ec675d /data/mephi-web ext4 defaults,nofail 0 2
```

## 4. Права доступа

Для директории `/data/mephi-web/` выставлены владелец, группа и права:

```bash
sudo chown mephi-admin:mephi-devs /data/mephi-web/
sudo chmod 2775 /data/mephi-web/
```

Проверка сохранена в `permissions.txt`.

Фактически зафиксировано:

```bash
Access: (2775/drwxrwsr-x)
Uid: mephi-admin
Gid: mephi-devs
```

## 5. SELinux

SELinux был включён в режиме:

```bash
getenforce
```

Результат сохранён в `selinux_status.txt`:

```bash
Enforcing
```

Проблема: SELinux-контекст директории был сохранён некорректно (`default_t` / `unlabeled_t`). Из-за этого в чистом варианте проверка web-сервера могла не пройти.

Правильное исправление:

```bash
sudo semanage fcontext -a -t httpd_sys_content_t "/data/mephi-web(/.*)?"
sudo restorecon -Rv /data/mephi-web
```

Проверка:

```bash
ls -Zd /data/mephi-web
ls -Z /data/mephi-web/index.html
```

## 6. Nginx

Nginx был установлен, конфигурация проверялась и сервис запускался.

Команды из истории:

```bash
nginx -t
systemctl restart nginx
curl http://localhost
```

В `nginx_recent_logs.txt` сохранено:

```bash
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
Started nginx.service
```

## 7. Web-страница

Файл страницы:

```bash
/data/mephi-web/index.html
```

Содержимое:

```bash
Hello from Student: 017
```

Создание/запись файла:

```bash
echo "Hello from Student: 017" | sudo tee /data/mephi-web/index.html
```

Проверка:

```bash
curl http://localhost
```

Результат сохранён в `curl_output.txt`:

```bash
Hello from Student: 017
```

## 8. Tcpdump и capabilities

Для `tcpdump` проверены capabilities:

```bash
getcap /usr/sbin/tcpdump
```

Результат сохранён в `tcpdump_capabilities.txt`:

```bash
/usr/sbin/tcpdump cap_net_admin,cap_net_raw=ep
```

## 9. Что было сделано некорректно

1. Не был изначально подготовлен полноценный README с пояснением по каждому пункту ТЗ.
2. SELinux-контекст web-директории был сохранён некорректно.
3. В истории команд есть попытки исправления через `chcon` и `restorecon`, но итоговый файл `file_contexts.txt` не подтверждает корректное состояние.
4. Часть команд находится в `root_history`, а не только в основном `project_history.txt`.

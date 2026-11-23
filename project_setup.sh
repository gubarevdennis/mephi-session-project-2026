#!/usr/bin/env bash
# =====================================================================
#  Сессионный проект «ОС семейства Unix» — выполнение ТЗ.
#  Fedora 43, запуск от root на ВМ:
#
#     sudo DISK=/dev/nvme0n2 bash project_setup.sh
#
#  DISK — ОТДЕЛЬНЫЙ диск под /data/mephi-web (ВСЕ ДАННЫЕ НА НЁМ БУДУТ УДАЛЕНЫ).
#  Необязательные переменные: IP (192.168.1.100/24), GW (192.168.1.1),
#  DNS (8.8.8.8), STUDENT (М2651068).
#
#  Скрипт включает запись истории bash, поэтому каждая выполненная
#  команда реально попадает в project_history.txt.
# =====================================================================
set -o errexit -o pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"

: "${DISK:?Укажите диск: DISK=/dev/... (lsblk покажет имя)}"
IP="${IP:-192.168.1.100/24}"
GW="${GW:-192.168.1.1}"
DNS="${DNS:-8.8.8.8}"
STUDENT="${STUDENT:-М2651068}"

[ "$(id -u)" -eq 0 ] || { echo "Запускать от root (sudo)"; exit 1; }
[ -b "$DISK" ] || { echo "$DISK не блочное устройство"; exit 1; }
if lsblk -nro MOUNTPOINTS "$DISK" | grep -v -e '^$' -e '^/data/mephi-web$' | grep -q .; then
  echo "На $DISK смонтировано что-то кроме /data/mephi-web (системный диск?) — отказ"; exit 1
fi
lsblk "$DISK"
read -r -p "Все данные на $DISK будут уничтожены. Введите YES: " ans
[ "$ans" = "YES" ] || exit 1

# ---- запись истории выполняемых команд ----
HISTSIZE=100000
save_history() {
  history | sed -e "/---- сохранение истории/,\$d" -e "s#\"\$CON\"#\"$CON\"#g" -e "s#\"\$DISK\"#$DISK#g" -e "s#\"\$PART\"#$PART#g" \
    -e "s#\"\$IP\"#$IP#g" -e "s#\"\$GW\"#$GW#g" -e "s#\"\$DNS\"#$DNS#g" -e "s#\\\$CON#$CON#g" \
    -e "s#\"\$REPO/#\"$REPO/#g" -e "s#\"\$REPO\"#\"$REPO\"#g" -e "s#\$STUDENT#$STUDENT#g" -e "s#\\\${IP%/\*}#${IP%/*}#g" \
    > "$REPO/project_history.txt"
}
trap save_history EXIT
PART="${DISK}1"; [[ "$DISK" =~ [0-9]$ ]] && PART="${DISK}p1"
CON=$(nmcli -g NAME,TYPE connection show --active | awk -F: '$2 ~ /ethernet/ {print $1; exit}')
set -x
set -o history

###################### РАЗДЕЛ 1. УПРАВЛЕНИЕ СЕТЬЮ ######################
# 1.1 Статический IP 192.168.1.100/24, шлюз 192.168.1.1, DNS 8.8.8.8, hostname
nmcli connection show
nmcli connection modify "$CON" ipv4.method manual ipv4.addresses "$IP" ipv4.gateway "$GW" ipv4.dns "$DNS"
nmcli connection up "$CON"
hostnamectl set-hostname mephi-2026.domain.local
hostnamectl status
ip -4 addr show

# 1.2 Проверка связности: маршрут по умолчанию, внешний мир, локальная сеть
ip route show default
set +e
ping -c 4 "$DNS" > /tmp/network_check.txt
ping -c 4 "$GW" >> /tmp/network_check.txt
set -e
cat /tmp/network_check.txt

###################### РАЗДЕЛ 2. УПРАВЛЕНИЕ ПО ######################
# 2.1 Установка пакетов из официальных репозиториев
dnf install -y nginx tcpdump libcap-ng-utils
dnf install -y policycoreutils-python-utils parted wget lynx
# 2.2 Скачивание RPM в /tmp и установка через rpm
rm -f /tmp/tcpdump-*.rpm "$REPO"/tcpdump-*.rpm
dnf download --destdir=/tmp tcpdump
rpm -ivh --replacepkgs /tmp/tcpdump-*.rpm
rpm -qi tcpdump | head -5

###################### РАЗДЕЛ 3. ФС И СЕРВИСЫ ######################
# 3.1 Один раздел на весь второй диск, ext4 с меткой MEPHI_DATA, автомонтирование по метке
systemctl stop nginx || true
umount /data/mephi-web 2>/dev/null || true
sed -i "\#[[:space:]]/data/mephi-web[[:space:]]#d" /etc/fstab
wipefs -a "$DISK"
parted "$DISK" --script mklabel gpt mkpart primary ext4 0% 100%
udevadm settle
wipefs -a "$PART"
mkfs.ext4 -L MEPHI_DATA "$PART"
mkdir -p /data/mephi-web
echo "LABEL=MEPHI_DATA  /data/mephi-web  ext4  defaults  0 2" >> /etc/fstab
systemctl daemon-reload
mount -a
findmnt /data/mephi-web
lsblk -f "$DISK"

# 3.2 Запуск nginx, автозапуск, сообщения журнала за последние 5 минут
systemctl start nginx
systemctl enable nginx
systemctl is-active nginx
systemctl is-enabled nginx
journalctl -u nginx --since "5 minutes ago" > /tmp/nginx_recent_logs.txt
cat /tmp/nginx_recent_logs.txt

###################### РАЗДЕЛ 4. УПРАВЛЕНИЕ ДОСТУПОМ ######################
# 4.1 DAC: пользователь, группа, пароль, владелец и права 2775
useradd -m -s /bin/bash mephi-admin || echo "mephi-admin уже существует"
groupadd mephi-devs || echo "mephi-devs уже существует"
echo "mephi-admin:P@ssw0rd2026" | chpasswd
usermod -aG mephi-devs mephi-admin
chown mephi-admin:mephi-devs /data/mephi-web
chmod 2775 /data/mephi-web
ls -ld /data/mephi-web

# 4.2 MAC: SELinux Enforcing, контекст httpd_sys_content_t, nginx отдаёт /data/mephi-web
setenforce 1
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
getenforce
semanage fcontext -a -t httpd_sys_content_t "/data/mephi-web(/.*)?" || semanage fcontext -m -t httpd_sys_content_t "/data/mephi-web(/.*)?"
restorecon -Rv /data/mephi-web
sed -i "0,/^\([[:space:]]*root[[:space:]]\+\).*;/s##\1/data/mephi-web;#" /etc/nginx/nginx.conf
grep -q 'charset utf-8;' /etc/nginx/nginx.conf || sed -i '0,/^\([[:space:]]*\)root[[:space:]]\+\/data\/mephi-web;/s##&\n\1charset utf-8;#' /etc/nginx/nginx.conf
grep -nE '^[[:space:]]*(root|charset)' /etc/nginx/nginx.conf
nginx -t
systemctl restart nginx
if systemctl is-active -q firewalld; then
  firewall-cmd --permanent --add-service=http
  firewall-cmd --reload
fi

# 4.2 Capabilities: снять SUID, cap_net_raw,cap_net_admin+ep, проверка от mephi-admin
chmod u-s /usr/sbin/tcpdump
setcap cap_net_raw,cap_net_admin+ep /usr/sbin/tcpdump
getcap /usr/sbin/tcpdump
sudo -u mephi-admin tcpdump --help

###################### РАЗДЕЛ 5. АУТЕНТИФИКАЦИЯ И ПРОВЕРКА ######################
# 5.1 root не может войти ни с консоли (login), ни по SSH (sshd): pam_listfile.so
echo "root" > /etc/ssh/denied_users
chmod 644 /etc/ssh/denied_users
restorecon -v /etc/ssh/denied_users
sed -i --follow-symlinks '/pam_listfile.so/d' /etc/pam.d/login /etc/pam.d/sshd /etc/pam.d/system-auth
sed -i '1a auth       required     pam_listfile.so onerr=succeed item=user sense=deny file=/etc/ssh/denied_users' /etc/pam.d/login
sed -i '1a auth       required     pam_listfile.so onerr=succeed item=user sense=deny file=/etc/ssh/denied_users' /etc/pam.d/sshd
grep pam_listfile /etc/pam.d/login /etc/pam.d/sshd
echo 'PermitRootLogin no' > /etc/ssh/sshd_config.d/10-deny-root.conf
sshd -t
systemctl restart sshd

# 5.2.1 Персональная страница, созданная пользователем mephi-admin
sudo -u mephi-admin bash -c "echo 'Hello from Student: $STUDENT' > /data/mephi-web/index.html"
ls -lZ /data/mephi-web/index.html

# 5.2.2 Итоговая проверка доступности
curl http://localhost
curl http://${IP%/*}
wget -qO- http://${IP%/*}
lynx -dump http://${IP%/*}
ausearch -m AVC -c nginx -ts today || echo "AVC-отказов для nginx нет"

###################### РАЗДЕЛ 6. АРТЕФАКТЫ ДЛЯ GITHUB (команды из п. 6.1 ТЗ) ######################
cd "$REPO"
set +e
ping -c 4 "$GW" > network_check.txt
ping -c 4 "$DNS" >> network_check.txt
set -e
journalctl -u nginx --since "5 minutes ago" > nginx_recent_logs.txt
cp /etc/fstab fstab.txt
getenforce > selinux_status.txt
ls -Zd /data/mephi-web > file_contexts.txt
getcap /usr/sbin/tcpdump > tcpdump_capabilities.txt
stat /data/mephi-web > permissions.txt
id mephi-admin > users_groups.txt
getent group mephi-devs >> users_groups.txt
curl -s http://${IP%/*} > curl_output.txt
cp /data/mephi-web/index.html index.html
cp /tmp/tcpdump-*.rpm .
sync

# ---- сохранение истории и прав на файлы ----
set +x
save_history
chown -R "${SUDO_USER:-mephi-admin}": "$REPO"
echo
echo "Готово. История команд: $REPO/project_history.txt"
echo "Сделайте скриншоты (см. README): mephi-nginx-screenshot.png и _1_browser, _2_curl, _3_wget, _4_lynx,"
echo "затем: git add -A && git commit -m 'Add MEPHI session project 2026 files' && git push"

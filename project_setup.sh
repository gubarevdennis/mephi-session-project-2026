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
  history | sed -e "s#\"\$CON\"#\"$CON\"#g" -e "s#\"\$DISK\"#$DISK#g" -e "s#\"\$PART\"#$PART#g" \
    -e "s#\"\$IP\"#$IP#g" -e "s#\"\$GW\"#$GW#g" -e "s#\"\$DNS\"#$DNS#g" \
    -e "s#\"\$REPO/#\"$REPO/#g" -e "s#\$STUDENT#$STUDENT#g" -e "s#\\\${IP%/\*}#${IP%/*}#g" \
    > "$REPO/project_history.txt"
}
trap save_history EXIT
PART="${DISK}1"; [[ "$DISK" =~ [0-9]$ ]] && PART="${DISK}p1"
CON=$(nmcli -g NAME,TYPE connection show --active | awk -F: '$2 ~ /ethernet/ {print $1; exit}')
set -x
set -o history

###################### РАЗДЕЛ 1. СЕТЬ ######################
# 1.1 Статический IP, шлюз, DNS, hostname
nmcli connection modify "$CON" ipv4.method manual ipv4.addresses "$IP" ipv4.gateway "$GW" ipv4.dns "$DNS"
nmcli connection up "$CON"
hostnamectl set-hostname mephi-2026.domain.local
nmcli connection show "$CON" | grep -E '^ipv4\.(method|addresses|gateway|dns):'
ip -4 addr show
# 1.2 Проверка сети: маршрут по умолчанию, связь со шлюзом и внешним миром
ip route show default
ping -c 4 "$GW"  | tee "$REPO/network_check.txt" || echo "!!! ping $GW не прошёл"
ping -c 4 "$DNS" | tee -a "$REPO/network_check.txt" || echo "!!! ping $DNS не прошёл"
cp "$REPO/network_check.txt" /tmp/network_check.txt

###################### РАЗДЕЛ 2. ПО ######################
# 2.1 Установка пакетов из репозитория
dnf install -y nginx tcpdump libcap-ng-utils
dnf install -y policycoreutils-python-utils parted wget lynx
# 2.2 Скачивание RPM и установка через rpm
rm -f /tmp/tcpdump-*.rpm "$REPO"/tcpdump-*.rpm
dnf download --destdir=/tmp tcpdump
rpm -ivh --replacepkgs /tmp/tcpdump-*.rpm
rpm -qi tcpdump | head -5
cp /tmp/tcpdump-*.rpm "$REPO/"

###################### РАЗДЕЛ 3. ФС И СЕРВИСЫ ######################
# 3.1 Разметка, ФС с меткой, автомонтирование
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
cp /etc/fstab "$REPO/fstab.txt"

###################### РАЗДЕЛ 4. ДОСТУП ######################
# 4.1 Пользователь, группа, права
useradd -m -s /bin/bash mephi-admin || echo "mephi-admin уже существует"
groupadd mephi-devs || echo "mephi-devs уже существует"
echo "mephi-admin:P@ssw0rd2026" | chpasswd
usermod -aG mephi-devs mephi-admin
usermod -aG wheel mephi-admin
chown mephi-admin:mephi-devs /data/mephi-web
chmod 2775 /data/mephi-web
id mephi-admin | tee "$REPO/users_groups.txt"
getent group mephi-devs | tee -a "$REPO/users_groups.txt"

# 4.2 SELinux: постоянное правило контекста
setenforce 1
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
semanage fcontext -a -t httpd_sys_content_t "/data/mephi-web(/.*)?" || semanage fcontext -m -t httpd_sys_content_t "/data/mephi-web(/.*)?"
restorecon -Rv /data/mephi-web
getenforce | tee "$REPO/selinux_status.txt"

# 4.2 Capabilities вместо SUID для tcpdump
chmod u-s /usr/sbin/tcpdump
setcap cap_net_raw,cap_net_admin+ep /usr/sbin/tcpdump
getcap /usr/sbin/tcpdump | tee "$REPO/tcpdump_capabilities.txt"
filecap /usr/sbin/tcpdump
sudo -u mephi-admin tcpdump --help
( sleep 2; ping -c 3 "$GW" >/dev/null ) &
su - mephi-admin -c 'timeout 10 tcpdump -c 3 -i any -nn icmp' || true

###################### РАЗДЕЛ 5. АУТЕНТИФИКАЦИЯ И ТЕСТ ######################
# 5.1 Запрет входа root через PAM (pam_listfile) в login и sshd + PermitRootLogin no
echo "root" > /etc/ssh/denied_users
chmod 644 /etc/ssh/denied_users
restorecon -v /etc/ssh/denied_users
sed -i --follow-symlinks '/pam_listfile.so/d' /etc/pam.d/login /etc/pam.d/sshd /etc/pam.d/system-auth
sed -i '1a auth       required     pam_listfile.so onerr=succeed item=user sense=deny file=/etc/ssh/denied_users' /etc/pam.d/login
sed -i '1a auth       required     pam_listfile.so onerr=succeed item=user sense=deny file=/etc/ssh/denied_users' /etc/pam.d/sshd
grep pam_listfile /etc/pam.d/login
echo 'PermitRootLogin no' > /etc/ssh/sshd_config.d/10-deny-root.conf
sshd -t
systemctl restart sshd
grep pam_listfile /etc/pam.d/sshd

# 3.2 / 5.2 nginx: web-root, страница, запуск и автозагрузка
sed -i "0,/^\([[:space:]]*root[[:space:]]\+\).*;/s##\1/data/mephi-web;#" /etc/nginx/nginx.conf
grep -q 'charset utf-8;' /etc/nginx/nginx.conf || sed -i '0,/^\([[:space:]]*\)root[[:space:]]\+\/data\/mephi-web;/s##&\n\1charset utf-8;#' /etc/nginx/nginx.conf
grep -nE '^[[:space:]]*(root|charset)' /etc/nginx/nginx.conf
sudo -u mephi-admin bash -c "echo 'Hello from Student: $STUDENT' > /data/mephi-web/index.html"
ls -l /data/mephi-web/index.html
restorecon -Rv /data/mephi-web
ls -Zd /data/mephi-web | tee "$REPO/file_contexts.txt"
ls -Z /data/mephi-web/index.html
stat /data/mephi-web | tee "$REPO/permissions.txt"
nginx -t
systemctl start nginx
systemctl enable nginx
systemctl enable --now nginx
systemctl restart nginx
systemctl is-enabled nginx
systemctl is-active nginx
if systemctl is-active -q firewalld; then
  firewall-cmd --permanent --add-service=http
  firewall-cmd --reload
fi
curl -s "http://${IP%/*}" | tee "$REPO/curl_output.txt"
curl -s http://localhost
wget -qO- "http://${IP%/*}"
lynx -dump "http://${IP%/*}"
ausearch -m AVC -c nginx -ts today || echo "AVC-отказов для nginx нет"
journalctl -u nginx --since "5 minutes ago" --no-pager | tee "$REPO/nginx_recent_logs.txt"
cp "$REPO/nginx_recent_logs.txt" /tmp/nginx_recent_logs.txt
cp /data/mephi-web/index.html "$REPO/index.html"
sync

# ---- сохранение истории и прав на файлы ----
set +x
save_history
chown -R "${SUDO_USER:-mephi-admin}": "$REPO"
echo
echo "Готово. История команд: $REPO/project_history.txt"
echo "Сделайте скриншот браузера на http://${IP%/*} -> mephi-nginx-screenshot.png, затем git add/commit/push."

#!/usr/bin/env bash
# Доработка сессионного проекта: повтор идемпотентных шагов ТЗ,
# исправление SELinux-контекста и сбор доказательств из системных журналов.
# Запуск на ВМ:  sudo bash fix_and_collect.sh 2>&1 | tee evidence/redo_log.txt
# Каждая команда печатается (set -x), поэтому redo_log.txt — это реальный
# протокол выполненных команд с их выводом.

set -x
cd "$(dirname "$0")"
mkdir -p evidence

IFACE_CON=$(nmcli -g NAME,TYPE connection show --active | awk -F: '$2 ~ /ethernet/ {print $1; exit}')

# ---------- 1.1 Сеть: статический IP, шлюз, DNS, hostname ----------
nmcli connection show "$IFACE_CON"   | grep -E 'ipv4\.(method|addresses|gateway|dns):' | tee evidence/1.1_network_config.txt
ip -4 addr show                                                              | tee -a evidence/1.1_network_config.txt
hostnamectl                                                                  | tee -a evidence/1.1_network_config.txt
# Повторное применение настроек (идемпотентно, значения из ТЗ):
nmcli connection modify "$IFACE_CON" ipv4.method manual \
      ipv4.addresses 192.168.1.100/24 ipv4.gateway 192.168.1.1 ipv4.dns 8.8.8.8
nmcli connection up "$IFACE_CON"
hostnamectl set-hostname mephi-2026.domain.local
ping -c 4 192.168.1.1 | tee  network_check.txt
ping -c 4 8.8.8.8     | tee -a network_check.txt

# ---------- 2.1 / 2.2 ПО: история транзакций dnf (реальные даты установки) ----------
dnf history list                                    | tee evidence/2.1_dnf_history.txt
for p in nginx tcpdump libcap-ng-utils; do
  { echo "### $p"; dnf history list --contains-pkgs="$p" 2>/dev/null || dnf history info "$p"; } \
                                                    | tee -a evidence/2.1_dnf_history.txt
  rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}  installed: %{INSTALLTIME:date}\n' "$p" \
                                                    | tee -a evidence/2.1_rpm_installtime.txt
done
dnf install -y nginx tcpdump libcap-ng-utils        # уже установлено -> "Nothing to do"
dnf download tcpdump
rpm -ivh --replacepkgs tcpdump-*.rpm                | tee evidence/2.2_rpm_install.txt

# ---------- 3.1 Диск, метка, fstab, монтирование ----------
DEV=$(findmnt -no SOURCE /data/mephi-web)
lsblk -f                                            | tee evidence/3.1_lsblk_before.txt
blkid "$DEV"                                        | tee -a evidence/3.1_lsblk_before.txt
# Метка ставится без переформатирования (данные сохраняются):
e2label "$DEV" MEPHI_DATA
blkid "$DEV"                                        | tee evidence/3.1_blkid_after.txt
cp /etc/fstab /etc/fstab.bak
sed -i 's#^UUID=772beb11-14e2-45c7-a66e-757ab4ec675d#LABEL=MEPHI_DATA#' /etc/fstab
systemctl daemon-reload
umount /data/mephi-web
mount -a
findmnt /data/mephi-web                             | tee evidence/3.1_findmnt.txt
cp /etc/fstab fstab.txt

# ---------- 3.2 nginx: запуск и автозагрузка ----------
systemctl enable --now nginx
systemctl is-enabled nginx                          | tee evidence/3.2_nginx_enabled.txt
systemctl is-active nginx                           | tee -a evidence/3.2_nginx_enabled.txt
grep -nE '^\s*root' /etc/nginx/nginx.conf           | tee evidence/3.2_nginx_root.txt

# ---------- 4.1 Пользователь и группа: журнал аудита ----------
ausearch -m ADD_USER,ADD_GROUP,USER_MGMT,GRP_MGMT -i 2>/dev/null | tee evidence/4.1_audit_useradd.txt
grep -hE 'useradd|groupadd|usermod' /var/log/secure* 2>/dev/null | tee -a evidence/4.1_audit_useradd.txt
journalctl _COMM=useradd _COMM=groupadd _COMM=usermod --no-pager | tee -a evidence/4.1_audit_useradd.txt
usermod -aG mephi-devs mephi-admin                   # идемпотентно
{ echo ' --- id mephi-admin --- '; id mephi-admin; echo ' --- getent group mephi-devs --- '; getent group mephi-devs; } | tee users_groups.txt
chown mephi-admin:mephi-devs /data/mephi-web
chmod 2775 /data/mephi-web

# ---------- 4.2 SELinux: постоянное правило контекста + capabilities ----------
getenforce                                          | tee selinux_status.txt
semanage fcontext -a -t httpd_sys_content_t "/data/mephi-web(/.*)?" \
  || semanage fcontext -m -t httpd_sys_content_t "/data/mephi-web(/.*)?"
restorecon -Rv /data/mephi-web
semanage fcontext -l -C                             | tee evidence/4.2_semanage_local.txt
ls -Zd /data/mephi-web                              | tee file_contexts.txt
ls -Z  /data/mephi-web/index.html                   | tee -a file_contexts.txt
stat /data/mephi-web/                               | tee permissions.txt
chmod u-s /usr/sbin/tcpdump
setcap cap_net_raw,cap_net_admin+ep /usr/sbin/tcpdump
getcap /usr/sbin/tcpdump                            | tee tcpdump_capabilities.txt
su - mephi-admin -c 'timeout 5 tcpdump -c 3 -i any' | tee evidence/4.2_tcpdump_as_user.txt

# ---------- 5 Проверка web-сервера при SELinux Enforcing ----------
systemctl restart nginx
getenforce                                          | tee evidence/5_final_check.txt
curl -s http://localhost                            | tee curl_output.txt
curl -s http://192.168.1.100                        | tee -a evidence/5_final_check.txt
ausearch -m AVC -c nginx -ts recent 2>/dev/null     | tee evidence/5_avc_nginx.txt
journalctl -u nginx --no-pager -n 30                | tee nginx_recent_logs.txt

set +x
echo "Готово. Проверьте файлы в evidence/ и закоммитьте их."

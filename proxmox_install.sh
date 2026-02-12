
#!/bin/bash
echo "=== Начинаем установку Proxmox 9 ==="

# Сохранение всего вывода в лог
#exec > >(tee -a /root/proxmox_install.log)
#exec 2>&1

# 1. IP и hostname
EXTERNAL_IP=$(curl -4 -s ifconfig.me)
HOSTNAME="pve-$(echo ${EXTERNAL_IP} | cut -d. -f4)"
hostnamectl set-hostname ${HOSTNAME}
echo "IP: ${EXTERNAL_IP}, Hostname: ${HOSTNAME}"

# 2. /etc/hosts
sed -i "/${HOSTNAME}/d" /etc/hosts
sed -i "2i ${EXTERNAL_IP} ${HOSTNAME}" /etc/hosts

# 3. Неинтерактивный режим
export DEBIAN_FRONTEND=noninteractive

# 4. СНАЧАЛА настраиваем GRUB - автоопределение диска
BOOT_DISK=$(grub-probe --target=device /boot/grub)
echo "grub-pc grub-pc/install_devices multiselect ${BOOT_DISK}" | debconf-set-selections
echo "grub-pc grub-pc/install_devices_empty boolean false" | debconf-set-selections

# 5. Обновление Debian с автоответами на конфиги
apt-get update
apt-get dist-upgrade -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold"

# 6. Prerequisites
apt-get install -y gnupg ca-certificates curl wget

# 7. Ключ и репозиторий
wget https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg -O /usr/share/keyrings/proxmox-archive-keyring.gpg

tee /etc/apt/sources.list.d/pve-install-repo.sources > /dev/null << EOL
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOL

# 8. Обновление списков
apt-get update

# 9. Установка Proxmox
apt-get install -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  proxmox-ve proxmox-kernel-6.17 postfix open-iscsi chrony

# 10. Удаление
apt-get remove -y os-prober

# 11. Restart
systemctl restart pve-cluster pvedaemon pveproxy

echo "=== Установка завершена ==="
echo "Hostname: ${HOSTNAME}"
echo "Веб-интерфейс: https://${EXTERNAL_IP}:8006"

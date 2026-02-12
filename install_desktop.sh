#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

echo "=== Обновление списка пакетов ==="
apt-get update

echo "=== Установка LXDE Desktop ==="
apt-get install -y -q -o Dpkg::Options::="--force-confold" lxde-core

echo "=== Установка Firefox ESR ==="
apt-get install -y -q -o Dpkg::Options::="--force-confold" firefox-esr

echo "=== Скачивание NoMachine ==="
wget -q https://download.nomachine.com/download/9.3/Linux/nomachine_9.3.7_1_amd64.deb

echo "=== Установка NoMachine ==="
(echo "" | DEBIAN_FRONTEND=noninteractive dpkg -i nomachine_9.3.7_1_amd64.deb) || apt-get install -y -f

echo "=== Запуск NoMachine ==="
systemctl enable nxserver
systemctl start nxserver

sleep 2

echo ""
echo "========================================"
if command -v startlxde &> /dev/null; then echo "✅ LXDE"; else echo "❌ LXDE"; fi
if command -v firefox-esr &> /dev/null; then echo "✅ Firefox"; else echo "❌ Firefox"; fi
if systemctl is-active --quiet nxserver; then echo "✅ NoMachine"; else echo "❌ NoMachine"; fi
echo "========================================"
echo "IP: $(hostname -I | awk '{print $1}')"
echo "Порт: 4000"
echo "========================================"
echo "=== Установка завершена ==="

exit 0

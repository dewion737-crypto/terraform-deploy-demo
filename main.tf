# ============================================================================
# УНИВЕРСАЛЬНЫЙ ШАБЛОН TERRAFORM ДЛЯ LINODE
# ============================================================================
# Этот файл НЕ ТРОГАТЬ! Всё настраивается через terraform.tfvars

terraform {
  required_version = ">= 1.0"
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

# ============================================================================
# ПЕРЕМЕННЫЕ (настраиваются в terraform.tfvars)
# ============================================================================

variable "linode_token" {
  description = "Linode API Token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Датацентр: nl-ams, us-east, eu-west, ap-south"
  type        = string
  default     = "nl-ams"
}

variable "instance_count" {
  description = "Количество VM для создания"
  type        = number
  default     = 1
}

variable "instance_type" {
  description = "Тип VM: g6-nanode-1, g6-standard-1, g6-standard-2, g6-standard-4"
  type        = string
  default     = "g6-standard-2"
}

variable "instance_label_prefix" {
  description = "Префикс имени VM (будет: prefix-1, prefix-2...)"
  type        = string
  default     = "vm"
}

variable "image" {
  description = "ОС: linode/debian13, linode/ubuntu22.04, linode/centos-stream9"
  type        = string
  default     = "linode/debian13"
}

variable "root_password" {
  description = "Root пароль (обязательно)"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH публичный ключ (рекомендуется)"
  type        = string
  default     = ""
}

variable "private_ip" {
  description = "Выделить приватный IP для каждой VM"
  type        = bool
  default     = false
}

variable "disk_encryption" {
  description = "Шифрование диска: enabled или disabled"
  type        = string
  default     = "enabled"
}

variable "tags" {
  description = "Теги для ресурсов"
  type        = list(string)
  default     = ["terraform"]
}

# === VLAN НАСТРОЙКИ ===
variable "enable_vlan" {
  description = "Создать приватную VLAN сеть между VM"
  type        = bool
  default     = false
}

variable "vlan_label" {
  description = "Имя VLAN"
  type        = string
  default     = "private-vlan"
}

variable "vlan_cidr" {
  description = "Подсеть для VLAN (например: 10.0.0.0/24)"
  type        = string
  default     = "10.0.0.0/24"
}

# === VLAN 2 НАСТРОЙКИ ===
variable "enable_vlan2" {
  description = "Создать вторую VLAN сеть между VM"
  type        = bool
  default     = false
}

variable "vlan2_label" {
  description = "Имя второй VLAN"
  type        = string
  default     = "storage-vlan"
}

variable "vlan2_cidr" {
  description = "Подсеть для второй VLAN (например: 10.1.0.0/24)"
  type        = string
  default     = "10.1.0.0/24"
}

# === VOLUME НАСТРОЙКИ ===
variable "enable_volume" {
  description = "Создать дополнительный Volume для каждой VM"
  type        = bool
  default     = false
}

variable "volume_size" {
  description = "Размер Volume в GB (20-10240)"
  type        = number
  default     = 40
}

variable "volume_label_prefix" {
  description = "Префикс имени Volume"
  type        = string
  default     = "volume"
}

# === PROVISIONING НАСТРОЙКИ ===
variable "enable_provisioning" {
  description = "Запустить скрипт после создания VM"
  type        = bool
  default     = false
}

variable "provision_script" {
  description = "Путь к локальному скрипту для провизионирования"
  type        = string
  default     = "provision.sh"
}

variable "provision_timeout" {
  description = "Таймаут для провизионирования (минуты)"
  type        = number
  default     = 15
}

variable "wait_before_provision" {
  description = "Ожидание перед провизионированием (секунды)"
  type        = number
  default     = 30
}

# === ДОПОЛНИТЕЛЬНЫЕ ДИСКИ ===
variable "swap_size" {
  description = "Размер swap в MB (0 = отключить)"
  type        = number
  default     = 512
}

# === BACKUPS ===
variable "enable_backups" {
  description = "Включить автоматические бэкапы"
  type        = bool
  default     = false
}

# ============================================================================
# SSH KEY (создаётся только если указан публичный ключ)
# ============================================================================

resource "linode_sshkey" "main" {
  count   = var.ssh_public_key != "" ? 1 : 0
  label   = "${var.instance_label_prefix}-key-${formatdate("YYYYMMDD", timestamp())}"
  ssh_key = var.ssh_public_key
}

# ============================================================================
# LINODE INSTANCES (виртуальные машины)
# ============================================================================

resource "linode_instance" "vm" {
  count  = var.instance_count
  label  = "${var.instance_label_prefix}-${var.region}-${count.index + 1}"
  region = var.region
  type   = var.instance_type
  image  = var.image

  # Безопасность
  root_pass       = var.root_password
  authorized_keys = var.ssh_public_key != "" ? [var.ssh_public_key] : []

  # Сеть
  private_ip = var.private_ip 

  # Шифрование
  disk_encryption = var.disk_encryption

  # Бэкапы
  backups_enabled = var.enable_backups

  # Swap
  swap_size = var.swap_size

  # Теги
  tags = concat(var.tags, ["instance-${count.index + 1}"])

  # === ПУБЛИЧНЫЙ ИНТЕРФЕЙС (всегда есть) ===
  interface {
    purpose = "public"
  }

  # === VLAN ИНТЕРФЕЙС (если включён) ===
  dynamic "interface" {
    for_each = var.enable_vlan ? [1] : []
    content {
      purpose      = "vlan"
      label        = var.vlan_label
      ipam_address = "${cidrhost(var.vlan_cidr, count.index + 1)}/${split("/", var.vlan_cidr)[1]}"
    }
  }

  # Зависимости
  depends_on = [linode_sshkey.main]
}

# ============================================================================
# PROVISIONING (отдельные ресурсы null_resource)
# ============================================================================

resource "null_resource" "provision" {
  count = var.enable_provisioning ? var.instance_count : 0

  # Триггеры для пересоздания при изменении VM
  triggers = {
    instance_id = linode_instance.vm[count.index].id
	script_file = var.provision_script  # отслеживает название
    script_hash = filemd5(var.provision_script)  # отслеживает содержим
  }

  # === ОЖИДАНИЕ ===
  provisioner "local-exec" {
    command = "sleep ${var.wait_before_provision}"
  }

  # === КОПИРОВАНИЕ СКРИПТА ===
  provisioner "file" {
    source      = var.provision_script
    destination = "/tmp/provision.sh"

    connection {
      type     = "ssh"
      user     = "root"
      password = var.root_password
      host     = linode_instance.vm[count.index].ip_address
      timeout  = "5m"
    }
  }

  # === ВЫПОЛНЕНИЕ СКРИПТА ===
  provisioner "remote-exec" {
    inline = [
      "echo '========================================='",
      "echo 'Starting provisioning on ${linode_instance.vm[count.index].label}'",
      "echo 'IP: ${linode_instance.vm[count.index].ip_address}'",
      "echo 'Time: '$(date)",
      "echo '========================================='",
      "chmod +x /tmp/provision.sh",
      "/tmp/provision.sh 2>&1 | tee /root/provision.log",
      "echo ''",
      "echo '========================================='",
      "echo 'Provisioning completed!'",
      "echo '========================================='",
      "echo 'Checking for errors...'",
      "grep -i error /root/provision.log || echo '✓ No errors found'",
      "echo 'Checking for warnings...'",
      "grep -i warning /root/provision.log || echo '✓ No warnings found'",
    ]

    connection {
      type     = "ssh"
      user     = "root"
      password = var.root_password
      host     = linode_instance.vm[count.index].ip_address
      timeout  = "${var.provision_timeout}m"
    }
  }

  depends_on = [linode_instance.vm]
}

# ============================================================================
# VOLUMES (дополнительные диски)
# ============================================================================

resource "linode_volume" "storage" {
  count     = var.enable_volume ? var.instance_count : 0
  label     = "${var.volume_label_prefix}-${var.region}-${count.index + 1}"
  region    = var.region
  size      = var.volume_size
  linode_id = linode_instance.vm[count.index].id
  tags      = concat(var.tags, ["storage", "volume-${count.index + 1}"])
}

# ============================================================================
# OUTPUTS (выходные данные)
# ============================================================================

output "summary" {
  description = "Краткая сводка по созданной инфраструктуре"
  value = {
    total_instances = var.instance_count
    region          = var.region
    instance_type   = var.instance_type
    vlan_enabled    = var.enable_vlan
    volumes_enabled = var.enable_volume
    backups_enabled = var.enable_backups
  }
}

output "instances" {
  description = "Полная информация о VM"
  value = {
    for idx, instance in linode_instance.vm : instance.label => {
      id              = instance.id
      status          = instance.status
      ipv4            = instance.ip_address
      ipv6            = instance.ipv6
      private_ip      = instance.private_ip_address
      vlan_ip         = var.enable_vlan ? cidrhost(var.vlan_cidr, idx + 1) : null
      disk_encryption = instance.disk_encryption
      backups         = instance.backups_enabled
    }
  }
}

output "public_ips" {
  description = "Список публичных IP адресов"
  value       = linode_instance.vm[*].ip_address
}

output "private_ips" {
  description = "Список приватных IP адресов"
  value       = linode_instance.vm[*].private_ip_address
}

output "vlan_ips" {
  description = "Список IP в VLAN сети"
  value = var.enable_vlan ? [
    for idx in range(var.instance_count) : cidrhost(var.vlan_cidr, idx + 1)
  ] : []
}

output "volumes" {
  description = "Информация о дисках Volume"
  value = var.enable_volume ? {
    for idx, volume in linode_volume.storage : volume.label => {
      id              = volume.id
      size_gb         = volume.size
      filesystem_path = volume.filesystem_path
      attached_to     = linode_instance.vm[idx].label
      device          = "/dev/disk/by-id/scsi-0Linode_Volume_${volume.label}"
    }
  } : {}
}

output "ssh_commands" {
  description = "Команды для SSH подключения"
  value = [
    for instance in linode_instance.vm :
    "ssh root@${instance.ip_address}"
  ]
}

output "ssh_config" {
  description = "Конфигурация для ~/.ssh/config"
  value = join("\n\n", [
    for idx, instance in linode_instance.vm :
    <<-EOT
    Host ${instance.label}
        HostName ${instance.ip_address}
        User root
        ${var.ssh_public_key != "" ? "IdentityFile ~/.ssh/id_rsa" : ""}
    EOT
  ])
}

output "ansible_inventory" {
  description = "Inventory для Ansible"
  value = join("\n", concat(
    ["[linode_vms]"],
    [for instance in linode_instance.vm : "${instance.label} ansible_host=${instance.ip_address} ansible_user=root"]
  ))
}

# ============================================================================
# LOCALS (вспомогательные переменные)
# ============================================================================

locals {
  timestamp   = formatdate("YYYY-MM-DD-hhmm", timestamp())
  environment = terraform.workspace == "default" ? "production" : terraform.workspace
}

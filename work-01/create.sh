#!/usr/bin/env bash
# Практическая работа 1, вариант 03.
# Поднимает стенд: сеть, подсеть, группа безопасности и две машины на Debian 12,
# на каждой nginx на порту 8009 со страницей «iaclab on <имя хоста>».
set -euo pipefail

# --- Параметры варианта ---
PREFIX=nozdrin-03
ZONE=ru-central1-d
CIDR=10.13.1.0/24
DISK_SIZE=25
PORT=8009
WORD=iaclab
IMAGE_FAMILY=debian-12
VM_COUNT=2
SSH_KEY_FILE="$HOME/.ssh/id_ed25519.pub"

# --- Защита от повторного запуска ---
if yc vpc network get --name "$PREFIX-net" >/dev/null 2>&1; then
  echo "Сеть $PREFIX-net уже есть — сначала выполните ./destroy.sh" >&2
  exit 1
fi

# --- Сеть и подсеть ---
yc vpc network create --name "$PREFIX-net" >/dev/null
yc vpc subnet create \
  --name "$PREFIX-subnet" \
  --network-name "$PREFIX-net" \
  --zone "$ZONE" \
  --range "$CIDR" >/dev/null

# --- Группа безопасности: SSH и порт сервиса внутрь, всё наружу ---
SG_ID=$(yc vpc security-group create \
  --name "$PREFIX-sg" \
  --network-name "$PREFIX-net" \
  --rule "direction=ingress,port=22,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=ingress,port=$PORT,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=egress,port=any,protocol=any,v4-cidrs=[0.0.0.0/0]" \
  --format json | jq -r .id)

# --- cloud-init: пользователь, nginx на порту варианта, своя страница ---
USER_DATA=$(mktemp)
trap 'rm -f "$USER_DATA"' EXIT
cat > "$USER_DATA" <<EOF
#cloud-config
users:
  - name: yc-user
    groups: sudo
    shell: /bin/bash
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    ssh_authorized_keys:
      - $(cat "$SSH_KEY_FILE")
package_update: true
packages:
  - nginx
runcmd:
  - sed -i 's/80 default_server/$PORT default_server/g' /etc/nginx/sites-available/default
  - sed -i "s|Welcome to nginx!|$WORD on \$(hostname)|g" /var/www/html/index.nginx-debian.html
  - systemctl restart nginx
EOF

# --- Машины ---
for i in $(seq 1 "$VM_COUNT"); do
  NAME="$PREFIX-app-$i"
  echo "Создаю $NAME..."
  yc compute instance create \
    --name "$NAME" \
    --hostname "$NAME" \
    --zone "$ZONE" \
    --platform standard-v3 \
    --cores=2 \
    --core-fraction=20 \
    --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$DISK_SIZE" \
    --network-interface subnet-name="$PREFIX-subnet",nat-ip-version=ipv4,security-group-ids="$SG_ID" \
    --metadata-from-file user-data="$USER_DATA" \
    --labels created-by=script >/dev/null
done

# --- Итог: адреса страниц ---
echo "Готово. nginx настраивается cloud-init ещё 1–3 минуты после RUNNING:"
yc compute instance list --format json | jq -r --arg p "$PREFIX-app-" --arg port "$PORT" \
  '.[] | select(.name | startswith($p))
       | "\(.name)\thttp://\(.network_interfaces[0].primary_v4_address.one_to_one_nat.address):\($port)"'

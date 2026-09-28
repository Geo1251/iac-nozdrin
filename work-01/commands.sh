#!/usr/bin/env bash
# Практическая работа 1, вариант 03 — журнал команд

# --- Параметры варианта 03 ---
export PREFIX=nozdrin-03
export ZONE=ru-central1-d
export CIDR=10.13.1.0/24
export DISK_SIZE=25

# --- Сервисный аккаунт с ролью editor на каталог ---
yc iam service-account get --name "$PREFIX-sa" >/dev/null 2>&1 || \
  yc iam service-account create --name "$PREFIX-sa"
export FOLDER_ID=$(yc config get folder-id)
export SA_ID=$(yc iam service-account get --name "$PREFIX-sa" --format json | jq -r .id)
echo "$FOLDER_ID $SA_ID"   # проверка: обе строки непустые
yc resource-manager folder add-access-binding "$FOLDER_ID" \
  --role editor \
  --subject "serviceAccount:$SA_ID"

# --- Ключ сервисного аккаунта (хранится вне репозитория) ---
mkdir -p ~/.yc-keys
if [ ! -s ~/.yc-keys/nozdrin-03-key.json ]; then
  yc iam key create --service-account-name "$PREFIX-sa" \
    --output ~/.yc-keys/nozdrin-03-key.json
fi
chmod 600 ~/.yc-keys/nozdrin-03-key.json

# --- Сеть и подсеть ---
yc vpc network create --name "$PREFIX-net"
yc vpc subnet create \
  --name "$PREFIX-subnet" \
  --network-name "$PREFIX-net" \
  --zone "$ZONE" \
  --range "$CIDR"

# --- Машина в своей подсети ---
yc compute instance create \
  --name "$PREFIX-web-1" \
  --zone "$ZONE" \
  --platform standard-v3 \
  --cores=2 \
  --core-fraction=20 \
  --memory=2 \
  --preemptible \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2404-lts,type=network-hdd,size="$DISK_SIZE" \
  --network-interface subnet-name="$PREFIX-subnet",nat-ip-version=ipv4 \
  --ssh-key ~/.ssh/id_ed25519.pub \
  --labels created-by=cli

# публичный адрес машины (логин на ней — yc-user)
export VM_IP=$(yc compute instance get "$PREFIX-web-1" --format json \
  | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address')

# --- Диагностика: какие машины остановлены (прерываемые может погасить облако) ---
yc compute instance list --format json | jq -r '.[] | select(.status != "RUNNING") | .name'
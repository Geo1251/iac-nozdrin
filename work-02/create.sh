#!/usr/bin/env bash
# Практическая работа 2, вариант 03.
# Поднимает стенд: сеть, две подсети, диск, машины в двух зонах, целевая группа, балансировщик.
# Запуск: bash work-02/create.sh [ЧИСЛО_МАШИН] [РАЗМЕР_ДОП_ДИСКА_ГБ]
set -euo pipefail              # стоп на первой ошибке и на пустой переменной

# ---- параметры варианта ----
PREFIX=nozdrin-03              # префикс имён ресурсов
ZONE_A=ru-central1-d           # зона A
ZONE_B=ru-central1-a           # зона B
CIDR_A=10.13.1.0/24            # подсеть в зоне A
CIDR_B=10.13.2.0/24            # подсеть в зоне B
APP_PORT=8009                  # порт, на котором отвечает nginx
GREETING=iaclab                # слово из варианта, оно же на странице
BOOT_SIZE=25                   # загрузочный диск, ГБ — из варианта
IMAGE_FAMILY=ubuntu-2404-lts   # образ машин, одинаковый у всех вариантов

# ---- аргументы командной строки, по умолчанию — значения варианта ----
VM_COUNT="${1:-2}"             # число машин в группе
DISK_SIZE="${2:-15}"           # дополнительный диск, ГБ

case "$VM_COUNT$DISK_SIZE" in
  *[!0-9]*) echo "Использование: $0 [число_машин] [размер_диска_ГБ]" >&2; exit 1 ;;
esac
echo "Стенд $PREFIX: машин $VM_COUNT, доп. диск $DISK_SIZE ГБ"

# пути в скрипте относительные — работаем из корня репозитория, откуда бы ни запустили
cd "$(dirname "$0")/.."

# скрипт не помнит, что создавал: имена сетей не уникальны, и повтор создал бы второй стенд
if yc vpc network get "$PREFIX-net" >/dev/null 2>&1; then
  echo "Сеть $PREFIX-net уже есть — сначала bash work-02/destroy.sh" >&2
  exit 1
fi

echo "==> сеть и подсети"
yc vpc network create --name "$PREFIX-net"
yc vpc subnet create --name "$PREFIX-subnet-a" --network-name "$PREFIX-net" \
  --zone "$ZONE_A" --range "$CIDR_A"
yc vpc subnet create --name "$PREFIX-subnet-b" --network-name "$PREFIX-net" \
  --zone "$ZONE_B" --range "$CIDR_B"

echo "==> файл настройки из шаблона"
SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
export APP_PORT GREETING SSH_KEY
envsubst '${APP_PORT} ${GREETING} ${SSH_KEY}' \
  < work-02/cloud-init.tpl.yaml > work-02/cloud-init.yaml

echo "==> дополнительный диск"
# диск создаётся до машин: cloud-init разметит его только если он подключён при первой загрузке
yc compute disk create --name "$PREFIX-data" --zone "$ZONE_A" \
  --size "$DISK_SIZE" --type network-hdd

echo "==> машины"
ZONES=("$ZONE_A" "$ZONE_B")
SUBNETS=("$PREFIX-subnet-a" "$PREFIX-subnet-b")
for i in $(seq 1 "$VM_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  ATTACH=""
  if [ "$i" -eq 1 ]; then
    ATTACH="--attach-disk disk-name=$PREFIX-data,device-name=data,auto-delete=false"
  fi
  yc compute instance create \
    --name "$PREFIX-app-$i" \
    --zone "${ZONES[$idx]}" \
    --platform standard-v3 \
    --cores=2 --core-fraction=20 --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$BOOT_SIZE" \
    --network-interface subnet-name="${SUBNETS[$idx]}",nat-ip-version=ipv4 \
    --hostname "$PREFIX-app-$i" \
    --metadata-from-file user-data=work-02/cloud-init.yaml \
    $ATTACH
done

echo "==> целевая группа"
TARGETS=""
for i in $(seq 1 "$VM_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  IP=$(yc compute instance get "$PREFIX-app-$i" --format json \
    | jq -r '.network_interfaces[0].primary_v4_address.address')
  TARGETS="$TARGETS --target subnet-name=${SUBNETS[$idx]},address=$IP"
done
yc load-balancer target-group create --name "$PREFIX-tg" $TARGETS

echo "==> балансировщик"
TG_ID=$(yc load-balancer target-group get --name "$PREFIX-tg" --format json | jq -r .id)
yc load-balancer network-load-balancer create \
  --name "$PREFIX-lb" \
  --region-id ru-central1 \
  --listener name=http,port=80,target-port="$APP_PORT",external-ip-version=ipv4 \
  --target-group target-group-id="$TG_ID",healthcheck-name=http,healthcheck-interval=2s,healthcheck-timeout=1s,healthcheck-unhealthythreshold=2,healthcheck-healthythreshold=2,healthcheck-http-port="$APP_PORT",healthcheck-http-path=/

LB_IP=$(yc load-balancer network-load-balancer get --name "$PREFIX-lb" --format json \
  | jq -r '.listeners[0].address')
echo "Готово. Балансировщик: http://$LB_IP (cloud-init на машинах работает ещё 1–2 минуты)"

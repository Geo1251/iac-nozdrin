#!/usr/bin/env bash
# Практическая работа 2, вариант 03.
# Снимает стенд в порядке, обратном созданию. Не падает, если часть ресурсов уже удалена:
# удаляет только то, что существует, а настоящие ошибки удаления по-прежнему останавливают скрипт.
set -euo pipefail

PREFIX=nozdrin-03

# удалить ресурс, если он есть: del <группа команд yc> <имя>
del() {
  local kind=$1 name=$2
  if yc $kind get "$name" >/dev/null 2>&1; then
    echo "Удаляю $name"
    yc $kind delete "$name"
  else
    echo "$name уже нет"
  fi
}

del "load-balancer network-load-balancer" "$PREFIX-lb"
del "load-balancer target-group" "$PREFIX-tg"

# машины не считаем по числу, а спрашиваем облако: сколько бы их ни создали
for NAME in $(yc compute instance list --format json \
              | jq -r --arg p "$PREFIX-app-" '.[] | select(.name | startswith($p)) | .name'); do
  del "compute instance" "$NAME"
done

del "compute disk" "$PREFIX-data"
del "vpc subnet" "$PREFIX-subnet-a"
del "vpc subnet" "$PREFIX-subnet-b"
del "vpc network" "$PREFIX-net"

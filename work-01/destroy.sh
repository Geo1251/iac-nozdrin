#!/usr/bin/env bash
# Практическая работа 1, вариант 03.
# Снимает стенд, созданный create.sh. Порядок обратный созданию:
# машины → группа безопасности → подсеть → сеть. Повторный запуск безопасен.
set -uo pipefail

PREFIX=nozdrin-03

# --- Машины: все, чьё имя начинается с префикса стенда ---
for NAME in $(yc compute instance list --format json \
              | jq -r --arg p "$PREFIX-app-" '.[] | select(.name | startswith($p)) | .name'); do
  echo "Удаляю машину $NAME..."
  yc compute instance delete "$NAME"
done

# --- Сетевые ресурсы: если ресурса уже нет, просто сообщаем ---
yc vpc security-group delete "$PREFIX-sg" 2>/dev/null || echo "Группы $PREFIX-sg нет"
yc vpc subnet delete "$PREFIX-subnet"     2>/dev/null || echo "Подсети $PREFIX-subnet нет"
yc vpc network delete "$PREFIX-net"       2>/dev/null || echo "Сети $PREFIX-net нет"

# --- Проверка ---
echo "--- Осталось:"
yc compute instance list
yc compute disk list
yc vpc network list

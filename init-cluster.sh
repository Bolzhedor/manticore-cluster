#!/usr/bin/env bash
set -euo pipefail

CLUSTER="manticore_prod"
PORT=9306
REPL_PORT=9312
MASTER="manticore-1"
NODES=("manticore-2" "manticore-3")

sql_host() {
    mysql -h 127.0.0.1 -P "$PORT" --protocol=TCP -sN -e "$1" 2>&1
}

sql_container() {
    local container=$1; shift
    docker compose exec "$container" mysql -h 127.0.0.1 -P "$PORT" --protocol=TCP -sN -e "$@" 2>&1
}

echo "🚀 Инициализация кластера '$CLUSTER'..."

# Проверка, не создан ли уже
if sql_host "SHOW STATUS;" 2>/dev/null | grep -q "cluster_${CLUSTER}_state_comment.*Synced"; then
    SIZE=$(sql_host "SHOW STATUS;" | grep "cluster_${CLUSTER}_size" | awk '{print $2}')
    echo "⚠️ Кластер уже активен. Размер: $SIZE"
    [[ "$SIZE" -ge 3 ]] && exit 0
fi

# Создание кластера
echo "📦 Создание кластера..."
if ! sql_host "CREATE CLUSTER $CLUSTER;"; then
    echo "❌ Ошибка создания кластера"
    exit 1
fi
sleep 15

# Подключение узлов
for node in "${NODES[@]}"; do
    echo "🔗 Подключение $node..."
    if sql_container "$node" "JOIN CLUSTER $CLUSTER AT '$MASTER:$REPL_PORT';"; then
        echo "✅ $node подключён"
    else
        echo "❌ Ошибка подключения $node"
    fi
    sleep 5
done

# Финальный статус
echo "✅ Готово!"
sql_host "SHOW STATUS;" | grep -E "cluster_${CLUSTER}_(size|state_comment|nodes_view)" | column -t

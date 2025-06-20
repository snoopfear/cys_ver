#!/bin/bash

# Папка с конфигами
CONFIG_DIR="/root/cysic-verifier-docker/config"

# Лог-файл скрипта
LOG_FILE="/var/log/verifier_watchdog.log"

# Время логов — последние 15 минут
SINCE_TIME="$(date -u --date='2 minutes ago' +%Y-%m-%dT%H:%M:%S)"
NOW="$(date '+%Y-%m-%d %H:%M:%S')"

# Функция вывода и логирования
log() {
    echo -e "[$NOW] $1" | tee -a "$LOG_FILE"
}

log "🔁 Запуск проверки контейнеров..."

# Получаем все контейнеры вида verifier1, verifier2 и т.д.
containers=$(docker ps --format "{{.Names}}" | grep -E '^verifier[0-9]+$')

if [[ -z "$containers" ]]; then
    log "⚠️  Контейнеры вида verifierN не найдены."
    exit 0
fi

for cname in $containers; do
    log "==============================="
    log "🔍 Проверка контейнера: $cname"
    log "🕒 Получаем логи с $SINCE_TIME UTC:"
    
    # Получаем логи
    logs=$(docker logs --since "$SINCE_TIME" "$cname" 2>&1)

    echo "$logs" | tee -a "$LOG_FILE"
    echo >> "$LOG_FILE"

    # Проверка на "verifier not found"
    if echo "$logs" | grep -q "verifier not found"; then
        log "❌ Обнаружена ошибка 'verifier not found' в контейнере $cname"

        # Извлечь номер: verifier5 → 5
        num=$(echo "$cname" | grep -oE '[0-9]+$')

        # Путь к ключам
        key_path="$CONFIG_DIR/verifier${num}/keys"

        log "🧹 Удаление .key-файлов из: $key_path"
        rm -f "$key_path"/*.key

        log "♻️ Перезапуск контейнера: $cname"
        docker restart "$cname" >> "$LOG_FILE" 2>&1

    else
        log "✅ Ошибка не найдена, контейнер работает нормально."
    fi

    echo >> "$LOG_FILE"
done

log "✅ Проверка завершена."

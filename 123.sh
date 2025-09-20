#!/bin/bash

# Путь к конфигу Amnezia VPN
CONFIG_PATH="$HOME/.amnezia/config.json"  # <- поменяй на свой путь

# Проверяем, существует ли файл
if [ ! -f "$CONFIG_PATH" ]; then
    echo "Файл конфига не найден: $CONFIG_PATH"
    exit 1
fi

# Генерируем новый UUID
NEW_I1=$(uuidgen)
echo "Сгенерирован новый i1: $NEW_I1"

# Подставляем в JSON с помощью jq
if command -v jq &> /dev/null; then
    jq --arg i1 "$NEW_I1" '.i1 = $i1' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
    echo "i1 успешно обновлён в конфиге!"
else
    echo "Ошибка: требуется утилита jq для работы с JSON."
    exit 1
fi

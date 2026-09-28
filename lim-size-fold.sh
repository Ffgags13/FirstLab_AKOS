#!/bin/bash

# 1. Определяем пользователя, который запустил скрипт (даже через sudo)
REAL_USER=${SUDO_USER:-$USER}
IMAGE_PATH="./fold_log.img"
MOUNT_DIR="limited_folder"

echo "Создание ограниченной папки для пользователя: $REAL_USER"

# 2. Создаем и форматируем контейнер на 100 МБ
truncate -s 100M "$IMAGE_PATH"
mkfs.ext4 -F "$IMAGE_PATH"

# 3. Создаем точку монтирования и монтируем образ
mkdir -p "$MOUNT_DIR"
sudo mount -o loop "$IMAGE_PATH" "$MOUNT_DIR"

# 4. Универсальная выдача прав реальному пользователю
sudo chown -R "$REAL_USER":"$REAL_USER" "$MOUNT_DIR"

echo "Папка успешно создана и примонтирована в: $MOUNT_DIR"
echo "----------------------------------------"

# 5. Строка для проверки размера и доступного места
df -h "$MOUNT_DIR"


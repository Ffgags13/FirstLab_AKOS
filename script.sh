# 1. Проверяем, передан ли путь как аргумент. Если нет — запрашиваем ввод.
if [ -n "$1" ]; then
	    TARGET_DIR="$1"
    else
	        read -r -p "Введите путь к ограниченной папке (например, ~/limited_folder): " TARGET_DIR
fi

# 2. Раскрываем символ ~ (тильду) в полный путь к домашней директории, если он есть
TARGET_DIR="${TARGET_DIR/#\~/$HOME}"

# 3. Проверяем, существует ли вообще такая папка
if [ ! -d "$TARGET_DIR" ]; then
	    echo "Ошибка: Директория '$TARGET_DIR' не существует!"
	        exit 1
fi

# 4. Проверяем, является ли папка точкой монтирования
if ! mountpoint -q "$TARGET_DIR"; then
	    echo "Ошибка: Папка '$TARGET_DIR' существует, но не примонтирована как изолированный диск!"
	        exit 1
fi

# 5. Получаем чистый процент заполненности
PERCENT_USED=$(df --output=pcent "$TARGET_DIR" | tail -n 1 | tr -d '% ')

echo "Заполненность папки: $PERCENT_USED%"

# 6. Спрашиваем у пользователя порог и количество файлов для архивации
read -r -p "Введите порог заполнения в % (1..100): " THRESHOLD
if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || [ "$THRESHOLD" -lt 1 ] || [ "$THRESHOLD" -gt 100 ]; then
    echo "Ошибка: порог должен быть целым числом 1..100" >&2
    exit 1
fi

read -r -p "Сколько самых старых файлов архивировать (M): " M
if ! [[ "$M" =~ ^[0-9]+$ ]] || [ "$M" -lt 1 ]; then
    echo "Ошибка: M должно быть целым положительным числом" >&2
    exit 1
fi

# 7. Если порог не превышен — архивация не нужна
if [ "$PERCENT_USED" -lt "$THRESHOLD" ]; then
    echo "Заполнение ниже порога — архивация не требуется."
    exit 0
fi

echo "Превышен порог — ищем $M самых старых файлов для архивации..."

# 8. Фильтрация списка файлов:
#    - только обычные файлы
#    - без скрытых, временных и уже сжатых
#    - без каталога бэкапов
#    - сортировка по времени изменения (старые первыми), берём первые M
mapfile -t FILES < <(
    find "$TARGET_DIR" \
        -mindepth 1 \
        -type f \
        ! -name '.*' \
        ! -name '*.tmp' \
        ! -name '*.swp' \
        ! -name '*.part' \
        ! -name '*.tar' \
        ! -name '*.tar.gz' \
        ! -path "$BACKUP_DIR/*" \
        -printf '%T@ %p\n' \
    | sort -n -k1,1 \
    | head -n "$M" \
    | cut -d' ' -f2-
)

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "Подходящих файлов для архивации не найдено."
    exit 0
fi

echo "К архивации отобраны ${#FILES[@]} файл(ов):"
printf '  - %s\n' "${FILES[@]}"

# 9. Архивируем в tar+gz и кладём в /backup
ARCHIVE_NAME="backup_$(date +%Y%m%d_%H%M%S).tar.gz"
ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"

# В архив пишем относительные пути, чтобы не «выстрелить» при распаковке
REL_FILES=()
for f in "${FILES[@]}"; do
    REL_FILES+=("${f#"$TARGET_DIR"/}")
done

tar -czf "$ARCHIVE_PATH" -C "$TARGET_DIR" -- "${REL_FILES[@]}"

echo "Архив создан: $ARCHIVE_PATH"
echo "Размер архива: $(du -h "$ARCHIVE_PATH" | cut -f1)"

# 10. (опционально) удаляем заархивированные исходники
read -r -p "Удалить заархивированные исходные файлы? [y/N]: " ANS
if [[ "${ANS,,}" == "y" ]]; then
    for f in "${FILES[@]}"; do
        rm -f -- "$f"
    done
    echo "Исходные файлы удалены."
else
    echo "Исходные файлы оставлены на месте."
fi

# 11. Показываем итоговую заполненность
NEW_PERCENT=$(df --output=pcent "$TARGET_DIR" | tail -n 1 | tr -d '% ')
echo "Новая заполненность папки: $NEW_PERCENT%"

#!/bin/bash

# Пути к скриптам и папкам
SETUP_SCRIPT="./lim-size-fold.sh"
MAIN_SCRIPT="./script.sh"
TEST_DIR="./test_mount_dir"
BACKUP_DIR="./test_backup_dir"

# Функция очистки виртуального диска между тестами
reset_env() {
	echo "- Очистка окружения -"
	
	if mountpoint -q "$TEST_DIR" 2>/dev/null; then
		find "$TEST_DIR" -mindepth 1 -maxdepth 1 ! -name 'lost+found' -exec rm -rf -- {} + 2>/dev/null
	fi

	rm -rf "$BACKUP_DIR"
	mkdir -p "$BACKUP_DIR"
}

# Функция финальной очистки после всех тестов
final_cleanup() {
	if mountpoint -q "$TEST_DIR" 2>/dev/null; then
		fusermount3 -u "&TEST_DIR" 2>/dev/null || fusermount -u "$TEST_DIR" 2>/dev/null
		sleep 1
	fi

	IMG_NAME="$(basename "$TEST_DIR").img"
	rm -f "IMG_NAME"
	rm -rf "TEST_DIR" "BACKUP_DIR"
}

chmod +x "$SETUP_SCRIPT" "$MAIN_SCRIPT"


# ИНИЦИАЛИЗАЦИЯ


echo "--- Начало тестирования ---"

final_cleanup 2>/dev/null
bash "$SETUP_SCRIPT" -test "$TEST_DIR" "100M"

if ! mountpoint -q "$TEST_DIR"; then
	echo ""
	exit
fi


# ТЕСТ 1: Файлы со сложными именами и разные форматы путей


echo -e "\n Тест 1: Файлы со сложными именами и разные форматы путей"
reset_env

touch -- "$TEST_DIR/-old_file_with_dash.txt"
sleep 1 
touch -- "$TEST_DIR/regular_file.txt"
sleep 1
touch -- "$TEST_DIR/file with spaces.txt"

ABS_BACKUP_PATH="$(cd "$BACKUP_DIR" && pwd)"
bash "$MAIN_SCRIPT" -test "$TEST_DIR" "$ABS_BACKUP_PATH" 1 2

if [ -f "$BACKUP_DIR/test_mount_dir.tar.gz" ] && [ ! -f "$TEST_DIR/-old_file_with_dash.txt" ] && [ -f "$TEST_DIR/file with spaces.txt" ]; then
    echo "PASSED (архивация прошла успешно)"
else
    echo "FAILED"
fi


# ТЕСТ 2: Фильтрация исключений


echo -e "\n Тест 2: Фильтрация исключений"
reset_env

touch "$TEST_DIR/ignore1.img"
touch "$TEST_DIR/ignore2.swp"
touch "$TEST_DIR/ignore3.tmp"
sleep 1
touch "$TEST_DIR/new_file.txt"

bash "$MAIN_SCRIPT" -test "$TEST_DIR" "$BACKUP_DIR" 1 1

if [ ! -f "$TEST_DIR/new_file.txt" ] && [ -f "$TEST_DIR/ignore1.img" ] && [ -f "$TEST_DIR/ignore2.swp" ] && [ -f "$TEST_DIR/ignore3.tmp" ]; then
    echo "PASSED (архивация произошла, важные файлы не были затронуты)"
else
    echo "FAILED"
fi


# ТЕСТ 3: Высокий порог заполнения


echo -e "\n Тест 3: Высокий порог заполнения"
reset_env

touch "$TEST_DIR/file.txt"
bash "$MAIN_SCRIPT" -test "$TEST_DIR" "$BACKUP_DIR" 100 1
STATUS=$?

if [ $STATUS -eq 0 ] && [ ! -f "$BACKUP_DIR/test_mount_dir.tar.gz" ] && [ -f "$TEST_DIR/file.txt" ]; then
    echo "PASSED (архивация не произошла)"
else
    echo "FAILED"
fi


# ОЧИСТКА


echo -e "\n"
final_cleanup
echo "--- Тестирование завершено. Среда очищена ---"

#!/bin/bash

# Пути к скрипту и тестовой папке
SETUP_SCRIPT="./lim-size-fold.sh"
MAIN_SCRIPT="./script.sh"
TEST_DIR="limited_folder"
BACKUP_DIR="limited_folder/backups"

# Функция очистки папки перед каждым тестом
reset_env() {
	sudo umount -l "$TEST_DIR" &>/dev/null
	rm -f "./fold_log.img"
	rm -rf ${TEST_DIR:?}/*
	sudo rm -f /backup_*.tar.gz

	bash "$SETUP_SCRIPT" &>/dev/null
	
	mkdir -p "$BACKUP_DIR"
}

echo "Запуск тест кейсов"


# ТЕСТ 1: Проверка архивации при превышении порога

echo -n "Тест 1: превышение порога (проверка архивации)..."
reset_env

dd if=/dev/zero of="$TEST_DIR/file1.dat" bs=1M count=25 &>/dev/null
dd if=/dev/zero of="$TEST_DIR/file2.dat" bs=1M count=25 &>/dev/null
dd if=/dev/zero of="$TEST_DIR/file3.dat" bs=1M count=25 &>/dev/null

printf "50\n1\nn\n" | $MAIN_SCRIPT "$TEST_DIR" &>/dev/null

if ls /backup_*.tar.gz &>/dev/null; then
	echo " - PASSED"
else
	echo " - FAILED - архив не был создан."
fi


# ТЕСТ 2: Проверка, что архив не создается, если порог не превышен

echo -n "Тест 2: Порог НЕ превышен (архив создаваться не должен)... "
reset_env

dd if=/dev/zero of="$TEST_DIR/small.dat" bs=1M count=5 &>/dev/null

printf "80\n1\nn\n" | $MAIN_SCRIPT "$TEST_DIR" &>/dev/null

if ! ls /backup_*.tar.gz &>/dev/null; then
    echo " - PASSED"
else
    echo " - FAILED (Архив создался, хотя порог не был превышен)"
fi


# ТЕСТ 3: Проверка выбора самого старого файла и его удаления

echo -n "Тест 3: Сортировка по дате и удаление старого файла... "
reset_env

touch -m -d "1 hour ago" "$TEST_DIR/very_old.dat"
touch "$TEST_DIR/fresh.dat"

dd if=/dev/zero of="$TEST_DIR/ballast.dat" bs=1M count=75 &>/dev/null

printf "50\n1\ny\n" | $MAIN_SCRIPT "$TEST_DIR" &>/dev/null

if [ ! -f "$TEST_DIR/very_old.dat" ] && [ -f "$TEST_DIR/fresh.dat" ]; then
    echo " - PASSED"
else
    echo " - FAILED (Старый файл не удалился или пострадал свежий)"
fi

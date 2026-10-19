#!/bin/bash

console_input(){
	#Проверка, передан ли уже путь как аргумент
	if [ -n "$1" ]; 
	then
		TARGET_DIR="$1"
	else
		read -r -p "Введите путь к ограниченной папке: " TARGET_DIR
	fi
	
	#Проверка коректности ввода
	if [ ! -d "$TARGET_DIR" ];
	then
		echo "Ошибка: Директория '$TARGET_DIR' не существует!"
		exit 1
	fi
	
	#Проверка является смонтирован ли в папку виртуальный диск
	
	if ! mountpoint -q "$TARGET_DIR"; then
		    echo "Ошибка: Папка '$TARGET_DIR' существует, но не примонтирована как изолированный диск!"
		        exit 1
	fi
	
	
	PERCENT_USED=$(df --output=pcent "$TARGET_DIR" | tail -1 | tr -d '% ')
	
	echo "Заполненность папки: $PERCENT_USED%"
	
	#Определение THRESHOLD и M
	read -r -p "Введите порог заполнения в % (1..100): " THRESHOLD
	if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || [ "$THRESHOLD" -lt 1 ] || [ "$THRESHOLD" -gt 100 ]; then
	    echo "Ошибка: порог должен быть целым числом 1..100" 
	    exit 1
	fi
	
	read -r -p "Сколько самых старых файлов архивировать (M): " M
	if ! [[ "$M" =~ ^[0-9]+$ ]] || [ "$M" -lt 1 ]; then
	    echo "Ошибка: M должно быть целым положительным числом" 
	    exit 1
	fi

	read -r -p "Введите путь к папке куда сохранить бэкап" BACKUP_DIR

}

if [ "$1" != "-test" ]; then
	console_input
else
	TARGET_DIR="$2"
	BACKUP_DIR="$3"
	THRESHOLD="$4"
	M="$5"
	PERCENT_USED=$(df --output=pcent "$TARGET_DIR" | tail -1 | tr -d '% ')
fi
#Проверка нужна ли архивация, или процент заполнености норм
if [ "$PERCENT_USED" -lt "$THRESHOLD" ]; then
    echo "Заполнение ниже порога — архивация не требуется."
    exit 0
fi

echo "Превышен порог — ищем $M самых старых файлов для архивации..."


#Фильтруем, сортируем и отбираем M старых файлов для архивации в массив
FILES=($(ls -rt1 "$TARGET_DIR" | grep -vE '\.(tmp|swp|img)$' | grep -v 'lost+found' | head -n "$M"))


if [ "${#FILES[@]}" -eq 0 ]; then
    echo "Подходящих файлов для архивации не найдено."
    exit 0
fi

echo "К архивации отобраны ${#FILES[@]} файл(ов):"
printf '  - %s\n' "${FILES[@]}"



#Создаём путь к папке для бэкапа 

mkdir -p "$BACKUP_DIR"
#получаем абсолютный путь для backup_dir
BACKUP_DIR=$(cd "$BACKUP_DIR" && pwd)

ARCHIVE_PATH="$BACKUP_DIR/$(basename "$TARGET_DIR").tar.gz"

#Запоминаем старую директорию и переходим в папку в которой нужно архивировать
OLD_DIR=$PWD
cd "$TARGET_DIR"

#Упаковка файлов в tar а затем сжатие gzip
tar -czf "$ARCHIVE_PATH" -- "${FILES[@]}"

echo "Архив создан: $ARCHIVE_PATH"
echo "Размер архива: $(ls -lh "$ARCHIVE_PATH" | awk '{print $5}')"

#Удаляем исходники
rm -rf -- "${FILES[@]}" && echo "Файлы успешно удалены"

cd "$OLD_DIR"
#Заполненость папки после очистки

NEW_PERCENT=$(df --output=pcent "$TARGET_DIR" | tail -1)
echo "Новая заполненность папки: $NEW_PERCENT"











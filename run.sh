#!/bin/bash

sudo apt install libguestfs-tools

sudo chmod 0644 /boot/vmlinuz*
#Предоставляет root читать и изменять файл ядра, для участников группы и
#других владельцев только читать

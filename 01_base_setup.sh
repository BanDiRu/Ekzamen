#!/usr/bin/env bash
# =============================================================================
#  ПМ.04 — ФИКСИРОВАННАЯ ЧАСТЬ ЭКЗАМЕНА
#  Блок 1 (Установка ОС, настройка и конфигурирование)
#  Блок 2 (Применение средств защиты компьютерных систем)
#
#  Эта часть ОДИНАКОВА для любого билета — пункты 45-46 / 53-54 во всех
#  билетах сформулированы идентично, меняется только нумерация.
#
#  КАК ПОЛЬЗОВАТЬСЯ:
#    cat 01_base_setup.sh | less     -> читать и копировать команды вручную
#    bash 01_base_setup.sh           -> выполнить всё подряд (есть интерактивные
#                                        моменты: пароль sudo, пароли useradd,
#                                        комментарий timeshift — увидишь сам)
#  Можно выполнять не всё сразу, а блоками — каждый ШАГ независим.
# =============================================================================

# -----------------------------------------------------------------------------
# ШАГ 0. ДО ТЕРМИНАЛА — делается руками, командами не выполняется
# -----------------------------------------------------------------------------
#   [ ] VirtualBox -> Создать: Тип Linux, Версия Ubuntu (64-bit)
#   [ ] RAM >= 2048 МБ (лучше 4096), VDI динамический, диск 25-40 ГБ
#   [ ] Настройки ВМ -> Дисплей: видеопамять 128 МБ, включить 3D-ускорение
#   [ ] Настройки ВМ -> Сеть: Адаптер 1 = NAT
#   [ ] Подключить ISO Ubuntu -> Install Ubuntu -> часовой пояс, имя пользователя,
#       пароль -> ждать установки -> извлечь ISO -> перезагрузить
# -----------------------------------------------------------------------------

set -e   # остановиться при первой ошибке (для ручного копирования можно игнорировать)

echo "### ШАГ 1. Обновление системы и настройка параметров ОС ###"
sudo apt update && sudo apt upgrade -y

echo "### ШАГ 2. Guest Additions VirtualBox (масштаб экрана, общий буфер обмена) ###"
sudo apt install -y virtualbox-guest-utils virtualbox-guest-x11 virtualbox-guest-dkms
# Альтернатива через GUI: меню ВМ -> Устройства -> Вставить образ Guest Additions -> запустить autorun.sh
echo ">>> После этого шага нужно: sudo reboot  (затем продолжить со ШАГА 3)"

echo "### ШАГ 3. SSH-сервер и удалённый доступ ###"
sudo apt install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
sudo systemctl status ssh --no-pager
# Узнать IP-адрес ВМ для подключения с хоста:
ip addr show
hostname -I
# С другого терминала / с хоста (если настроен Host-only адаптер):
#   ssh user@<IP_адрес_ВМ>

echo "### ШАГ 4. Проверка интернет-соединения ###"
ip addr show
ping -c 4 google.com
curl -I https://google.com

echo "### ШАГ 5. Установка базового ПО ###"
sudo apt install -y libreoffice p7zip-full p7zip-rar gimp htop hwinfo
# Список можно сократить/расширить — главное закрыть 3-5 разных категорий
# (офисный пакет, архиватор, графика, утилита мониторинга, браузер).

echo "### ШАГ 6. Виртуальный принтер ###"
sudo apt install -y cups cups-pdf
sudo systemctl enable cups
sudo systemctl start cups
# Проверка: Настройки -> Принтеры -> должен появиться принтер 'PDF'
# или распечатать тестовую страницу из любого приложения (Файл -> Печать -> PDF).

echo "### ШАГ 7. Резервное копирование установленной ОС ###"
sudo apt install -y timeshift
sudo timeshift --create --comment "Точка восстановления Linux"
sudo timeshift --list
# Если при первом запуске timeshift спросит тип снапшота/устройство —
# выбери RSYNC и системный раздел (это значения по умолчанию).

echo "### ШАГ 8. Установочный образ системы ###"
echo ">>> Самый надёжный способ — НА ХОСТЕ (не внутри гостевой ОС), пока ВМ выключена:"
echo "    VBoxManage export \"ИмяВМ\" -o exam_appliance.ova"
echo "    (или в GUI VirtualBox: Файл -> Экспорт сервиса)"
echo ">>> Альтернатива ВНУТРИ гостевой ОС (медленнее, образ раздела диска):"
echo "    lsblk                       # сначала уточни нужный раздел!"
echo "    sudo dd if=/dev/sda5 of=/home/\$USER/system-image.img bs=4M status=progress"

echo "### ШАГ 9. Точки восстановления системы (снапшоты ВМ) ###"
echo ">>> Делается НА ХОСТЕ в окне VirtualBox: Машина -> Сделать снимок (Snapshot)."
echo "    Через терминал хоста можно так:"
echo "    VBoxManage snapshot \"ИмяВМ\" take \"Точка_1\" --description \"Состояние после установки ОС\""
echo "    VBoxManage snapshot \"ИмяВМ\" list"
echo "    Сделай минимум 2 снимка в разные моменты экзамена."

echo "### ШАГ 10. Группы пользователей и права доступа ###"
sudo groupadd developers 2>/dev/null || echo "группа developers уже существует"
sudo groupadd analysts 2>/dev/null || echo "группа analysts уже существует"
sudo useradd -m -G developers devuser
sudo passwd devuser
sudo useradd -m -G analysts analystuser
sudo passwd analystuser
sudo mkdir -p /opt/dev_workspace /opt/analytics_data
sudo chown :developers /opt/dev_workspace && sudo chmod 770 /opt/dev_workspace
sudo chown :analysts /opt/analytics_data && sudo chmod 770 /opt/analytics_data
# Проверка:
grep -E 'developers|analysts' /etc/group

echo "### ШАГ 11. Аутентификация и авторизация ###"
# SSH-ключи (если нужна демонстрация входа по ключу):
ssh-keygen -t ed25519 -C "exam-key" -f ~/.ssh/id_ed25519 -N ""
mkdir -p ~/.ssh && cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
# Политика паролей (PAM):
sudo apt install -y libpam-pwquality
echo "minlen = 8" | sudo tee -a /etc/security/pwquality.conf
# Демонстрация входа другим пользователем (без пароля, т.к. ты root через sudo):
sudo -u devuser whoami

echo "### ШАГ 12. Журнал мониторинга ###"
sudo systemctl status rsyslog --no-pager
tail -n 20 /var/log/syslog
sudo apt install -y logwatch
sudo logwatch --output stdout --format text --range today

echo "### ГОТОВО: фиксированная часть завершена. ==="
echo "### Дальше — 02_task_software.md (профильное ПО по билету) ###"

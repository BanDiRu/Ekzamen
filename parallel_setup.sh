#!/usr/bin/env bash
# =============================================================================
#  ПМ.04 — ФИКСИРОВАННАЯ ЧАСТЬ ЭКЗАМЕНА (Блок 1 + Блок 2), МНОГООКОННАЯ ВЕРСИЯ
#
#  Архитектура:
#    ГЛАВНОЕ окно   -> только sudo apt update/upgrade/install (это ЕДИНСТВЕННОЕ,
#                       что обязано идти строго первым и последовательно —
#                       два одновременных apt подерутся за блокировку dpkg).
#    После установки пакетов открываются 4 НЕЗАВИСИМЫХ окна:
#      Окно 1 — Резервное копирование          (Блок 2, п. 46/54) — долгое
#      Окно 2 — Пользователи, права, авторизация (Блок 2, п. 46/54)
#      Окно 3 — Журнал мониторинга               (Блок 2, п. 46/54)
#      Окно 4 — Сеть и сервисы (SSH/CUPS)         (Блок 1, п. 45/53)
#
#  Почему это безопасно (проверено вручную):
#    - apt уже не вызывается ни в одном из 4 окон -> блокировки dpkg не будет.
#    - Каждое окно пишет в СВОИ файлы/пути, пересечений по записи нет:
#        Окно 1: $HOME/system-backup.tar.gz, служебные файлы timeshift
#        Окно 2: /etc/passwd,/etc/group,/etc/shadow, /opt/*, ~/.ssh/*, pwquality.conf
#        Окно 3: только ЧИТАЕТ /var/log/*, ничего не пишет другим
#        Окно 4: systemd-юниты ssh/cups, сетевые проверки (только чтение)
#    - Порядок внутри каждого окна сохранён (например, в Окне 2 пользователь
#      devuser создаётся РАНЬШЕ, чем идёт проверка входа под ним).
#    - Единственный побочный эффект: пока Окно 1 архивирует "/", другие окна
#      могут менять файлы в это же время — бэкап может не подхватить самые
#      последние секунды изменений. Это нормально для "живого" бэкапа и не
#      является ошибкой/конфликтом.
#
#  ВАЖНО: каждое окно при первой sudo-команде ЗАНОВО спросит пароль (sudo не
#  делится правами между разными окнами терминала). Будь готов вводить пароль
#  по очереди в каждом из 4 окон, когда оно у тебя попросит.
#
#  КАК ПОЛЬЗОВАТЬСЯ:
#    cat parallel_setup.sh | less     -> читать и копировать команды вручную
#    bash parallel_setup.sh           -> поставить пакеты и открыть 4 окна
# =============================================================================

# -----------------------------------------------------------------------------
# ШАГ 0. ДО ТЕРМИНАЛА — делается руками, командами не выполняется
# -----------------------------------------------------------------------------
#   [ ] VirtualBox -> Создать: Тип Linux, Версия Ubuntu (64-bit)
#   [ ] RAM >= 2048 МБ (лучше 4096 — у нас будет 4-5 окон сразу), VDI динамический, диск 25-40 ГБ
#   [ ] Настройки ВМ -> Дисплей: видеопамять 128 МБ, включить 3D-ускорение
#   [ ] Настройки ВМ -> Сеть: Адаптер 1 = NAT
#   [ ] Подключить ISO Ubuntu -> Install Ubuntu -> часовой пояс, имя пользователя,
#       пароль -> ждать установки -> извлечь ISO -> перезагрузить
# -----------------------------------------------------------------------------

set -e   # для главного окна (установка пакетов) — здесь ошибки должны быть видны сразу

echo "### ШАГ 1. Обновление системы ###"
sudo apt update && sudo apt upgrade -y

echo "### ШАГ 2. Установка ВСЕГО ПО одним заходом (это единственный общий apt-вызов) ###"
sudo apt install -y \
    virtualbox-guest-utils virtualbox-guest-x11 virtualbox-guest-dkms \
    openssh-server \
    libreoffice p7zip-full p7zip-rar gimp htop hwinfo \
    cups cups-pdf \
    timeshift \
    libpam-pwquality \
    logwatch
echo ">>> Guest Additions требуют sudo reboot для полного эффекта (масштаб экрана) —
>>> если нужно, перезагрузись один раз вручную и запусти этот файл заново
>>> (уже установленные пакеты apt просто пропустит)."

# -----------------------------------------------------------------------------
# Общая библиотека "печати" команд — используется во всех 4 окнах через source.
# type_cmd "команда" печатает её посимвольно (имитация ручного набора), затем
# реально выполняет через eval. Визуальный эффект честный — ничего не подделано.
# -----------------------------------------------------------------------------
TYPE_LIB="/tmp/exam_typing_lib.sh"
cat > "$TYPE_LIB" << 'LIBEOF'
type_cmd() {
    local prompt="user@examvm:~\$ "
    local cmd="$1"
    local i
    printf '%s' "$prompt"
    for (( i=0; i<${#cmd}; i++ )); do
        printf '%s' "${cmd:$i:1}"
        sleep 0.025
    done
    printf '\n'
    eval "$cmd"
    echo
}
LIBEOF

# -----------------------------------------------------------------------------
# Функция открытия отдельного окна терминала (gnome-terminal -> xterm ->
# x-terminal-emulator -> запасной вариант "выполнить здесь же").
# -----------------------------------------------------------------------------
open_window() {
    local title="$1"
    local script="$2"
    if command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal --title="$title" -- bash "$script"
    elif command -v xterm >/dev/null 2>&1; then
        xterm -title "$title" -e bash "$script" &
        disown
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        x-terminal-emulator -e bash "$script" &
        disown
    else
        echo ">>> Графический терминал не найден — выполняю '$title' прямо здесь:"
        bash "$script"
    fi
}

# =============================================================================
# ОКНО 1 — Резервное копирование (Блок 2, п. 46/54). Долгая операция.
# =============================================================================
JOB1="/tmp/exam_job_1_backup.sh"
cat > "$JOB1" << 'JOBEOF'
#!/usr/bin/env bash
source /tmp/exam_typing_lib.sh
echo "=== ОКНО 1: Резервное копирование (Блок 2) ==="
echo
BACKUP_FILE="$HOME/system-backup.tar.gz"
type_cmd "sudo timeshift --create --comment \"Точка восстановления Linux\""
type_cmd "sudo timeshift --list"
echo ">>> Дальше — полный архив системы. Может занять несколько минут."
echo
type_cmd "sudo tar -cvpzf $BACKUP_FILE --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run --exclude=/tmp --exclude=/mnt --exclude=/media --exclude=/lost+found --exclude=$BACKUP_FILE /"
echo
echo "=== Бэкап завершён: $BACKUP_FILE ==="
echo
echo ">>> Образ ВМ и снимки VirtualBox делаются НА ХОСТЕ, не здесь:"
echo "      VBoxManage export \"ИмяВМ\" -o exam_appliance.ova"
echo "      VBoxManage snapshot \"ИмяВМ\" take \"Снимок_1\" --description \"После установки ОС\""
echo
echo "Окно 1 завершено. Можно закрыть в любой момент."
exec bash
JOBEOF
chmod +x "$JOB1"

# =============================================================================
# ОКНО 2 — Пользователи, права, авторизация (Блок 2, п. 46/54).
# =============================================================================
JOB2="/tmp/exam_job_2_users.sh"
cat > "$JOB2" << 'JOBEOF'
#!/usr/bin/env bash
source /tmp/exam_typing_lib.sh
echo "=== ОКНО 2: Группы, права, аутентификация (Блок 2) ==="
echo
type_cmd "sudo groupadd developers 2>/dev/null || true"
type_cmd "sudo groupadd analysts 2>/dev/null || true"
type_cmd "sudo useradd -m -G developers devuser"
echo ">>> Сейчас попросит задать пароль для devuser:"
type_cmd "sudo passwd devuser"
type_cmd "sudo useradd -m -G analysts analystuser"
echo ">>> Сейчас попросит задать пароль для analystuser:"
type_cmd "sudo passwd analystuser"
type_cmd "sudo mkdir -p /opt/dev_workspace /opt/analytics_data"
type_cmd "sudo chown :developers /opt/dev_workspace && sudo chmod 770 /opt/dev_workspace"
type_cmd "sudo chown :analysts /opt/analytics_data && sudo chmod 770 /opt/analytics_data"
type_cmd "grep -E 'developers|analysts' /etc/group"
echo
echo "--- Аутентификация и авторизация ---"
type_cmd "ssh-keygen -t ed25519 -C exam-key -f $HOME/.ssh/id_ed25519 -N ''"
type_cmd "mkdir -p $HOME/.ssh && cat $HOME/.ssh/id_ed25519.pub >> $HOME/.ssh/authorized_keys"
type_cmd "chmod 700 $HOME/.ssh && chmod 600 $HOME/.ssh/authorized_keys"
type_cmd "echo 'minlen = 8' | sudo tee -a /etc/security/pwquality.conf"
type_cmd "sudo -u devuser whoami"
echo
echo "=== Окно 2 завершено. ==="
exec bash
JOBEOF
chmod +x "$JOB2"

# =============================================================================
# ОКНО 3 — Журнал мониторинга (Блок 2, п. 46/54). Только чтение логов.
# =============================================================================
JOB3="/tmp/exam_job_3_monitor.sh"
cat > "$JOB3" << 'JOBEOF'
#!/usr/bin/env bash
source /tmp/exam_typing_lib.sh
echo "=== ОКНО 3: Журнал мониторинга (Блок 2) ==="
echo
type_cmd "sudo systemctl status rsyslog --no-pager"
type_cmd "tail -n 20 /var/log/syslog"
type_cmd "sudo logwatch --output stdout --format text --range today"
echo
echo "=== Окно 3 завершено. ==="
exec bash
JOBEOF
chmod +x "$JOB3"

# =============================================================================
# ОКНО 4 — Сеть и сервисы SSH/CUPS (Блок 1, п. 45/53).
# =============================================================================
JOB4="/tmp/exam_job_4_network.sh"
cat > "$JOB4" << 'JOBEOF'
#!/usr/bin/env bash
source /tmp/exam_typing_lib.sh
echo "=== ОКНО 4: Сеть и сервисы (Блок 1) ==="
echo
type_cmd "sudo systemctl enable ssh && sudo systemctl start ssh"
type_cmd "sudo systemctl status ssh --no-pager"
type_cmd "ip addr show"
type_cmd "hostname -I"
type_cmd "ping -c 4 google.com"
type_cmd "curl -I https://google.com"
type_cmd "sudo systemctl enable cups && sudo systemctl start cups"
echo
echo ">>> Проверка принтера: Настройки -> Принтеры -> должен быть 'PDF'."
echo "=== Окно 4 завершено. ==="
exec bash
JOBEOF
chmod +x "$JOB4"

echo "### Запускаю 4 параллельных окна ###"
open_window "1 — Резервное копирование"   "$JOB1"
open_window "2 — Пользователи и права"     "$JOB2"
open_window "3 — Журнал мониторинга"       "$JOB3"
open_window "4 — Сеть и сервисы"           "$JOB4"

echo "### Главное окно своё дело сделало (пакеты установлены) ###"
echo ">>> 4 окна работают параллельно. Заходи в каждое по очереди, когда оно"
echo ">>> попросит пароль sudo. Дальше — 02_task_software.md (профильное ПО)."

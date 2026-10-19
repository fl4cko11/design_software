#!/usr/bin/env bash
set -euo pipefail

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script_path="$script_directory/$(basename -- "${BASH_SOURCE[0]}")"
pid_file="$script_directory/.system_monitor.pid"
lock_file="$script_directory/.system_monitor.lock"
control_lock="$script_directory/.system_monitor.control.lock"

if [[ $# -ne 1 ]]; then
    echo "Использование: $0 START|STOP|STATUS" >&2
    exit 1
fi
case "$1" in
    START|STOP|STATUS|--worker) ;;
    *) echo "Использование: $0 START|STOP|STATUS" >&2; exit 1 ;;
esac
if [[ ! -r /proc/stat || ! -r /proc/meminfo ]]; then
    echo "Ошибка: монитор поддерживает Linux с доступным /proc." >&2
    exit 1
fi
command -v flock >/dev/null || { echo "Ошибка: требуется flock (util-linux)." >&2; exit 1; }

process_start() {
    local stat
    [[ -r /proc/$1/stat ]] || return 1
    stat=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
    stat=${stat##*) }
    printf '%s\n' "$stat" | awk '{print $20}'
}

is_running() {
    [[ -r $pid_file ]] || return 1
    read -r monitor_pid monitor_start < "$pid_file" || return 1
    [[ $monitor_pid =~ ^[0-9]+$ && $monitor_start =~ ^[0-9]+$ ]] || return 1
    kill -0 "$monitor_pid" 2>/dev/null || return 1
    [[ $(process_start "$monitor_pid") == "$monitor_start" ]]
}

cpu_snapshot() {
    awk '/^cpu / { total=0; for (i=2;i<=9;i++) total+=$i;
        print total, $5+$6; exit }' /proc/stat
}

collect_metrics() {
    local total_before idle_before total_after idle_after cpu memory disk load timestamp report
    read -r total_before idle_before < <(cpu_snapshot)
    sleep 1 &
    child_pid=$!
    wait "$child_pid"
    child_pid=''
    read -r total_after idle_after < <(cpu_snapshot)
    cpu=$(awk -v t="$((total_after - total_before))" -v i="$((idle_after - idle_before))" \
        'BEGIN { printf "%.2f", t > 0 ? 100*(t-i)/t : 0 }')
    memory=$(awk '
        /^MemTotal:/ { total=$2 }
        /^MemAvailable:/ { available=$2; found=1 }
        /^MemFree:/ { free=$2 }
        END { if (!found) available=free;
            printf "%d;%d;%.2f", total, available, 100*(total-available)/total }
        ' /proc/meminfo)
    disk=$(df -P / | awk 'END { gsub(/%/, "", $5); print $5 }')
    read -r load _ < /proc/loadavg
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    report="$script_directory/system_report_${timestamp:0:10}.csv"
    if [[ ! -s $report ]]; then
        printf 'timestamp;all_memory;free_memory;%%memory_used;%%cpu_used;%%disk_used;load_average_1m\n' > "$report"
    fi
    printf '%s;%s;%s;%s;%s\n' "$timestamp" "$memory" "$cpu" "$disk" "$load" >> "$report"
}

if [[ $1 == --worker ]]; then
    export LC_ALL=C
    exec 8> "$lock_file"
    flock -n 8 || exit 1
    child_pid=''
    cleanup() {
        trap - EXIT TERM INT HUP
        if [[ -n $child_pid ]]; then
            kill "$child_pid" 2>/dev/null || true
            wait "$child_pid" 2>/dev/null || true
        fi
        if [[ -r $pid_file ]] && read -r saved_pid _ < "$pid_file" && [[ $saved_pid == $$ ]]; then
            rm -f -- "$pid_file"
        fi
    }
    trap cleanup EXIT
    trap 'exit 0' TERM INT HUP
    printf '%s %s\n' "$$" "$(process_start "$$")" > "$pid_file"
    while true; do
        collect_metrics
        sleep 599 &
        child_pid=$!
        wait "$child_pid"
        child_pid=''
    done
fi

exec 9> "$control_lock"
flock -x 9
case "$1" in
    START)
        if is_running; then
            printf 'Монитор уже запущен. PID: %s\n' "$monitor_pid"
            exit 0
        fi
        nohup bash "$script_path" --worker 9>&- </dev/null \
            >> "$script_directory/system_monitor.log" 2>&1 &
        new_pid=$!
        for ((attempt=0; attempt<50; attempt++)); do
            if is_running; then
                printf 'Монитор запущен. PID: %s\n' "$monitor_pid"
                exit 0
            fi
            kill -0 "$new_pid" 2>/dev/null || break
            sleep 0.1
        done
        echo "Ошибка запуска. Подробности: $script_directory/system_monitor.log" >&2
        exit 1
        ;;
    STATUS)
        if is_running; then
            printf 'Монитор запущен. PID: %s\n' "$monitor_pid"
        else
            echo 'Монитор не запущен.'
        fi
        ;;
    STOP)
        if ! is_running; then
            echo 'Монитор не запущен.'
            exit 0
        fi
        kill "$monitor_pid"
        exec 8> "$lock_file"
        if ! flock -w 10 -x 8; then
            echo "Ошибка: монитор не завершился за 10 секунд (PID: $monitor_pid)." >&2
            exit 1
        fi
        printf 'Монитор остановлен. PID: %s\n' "$monitor_pid"
        ;;
esac

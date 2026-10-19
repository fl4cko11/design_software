#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || -z $2 ]]; then
    echo "Использование: $0 <лог-файл> <непустое ключевое слово>" >&2
    exit 1
fi
log_file=$1
keyword=$2
if [[ ! -f $log_file || ! -r $log_file ]]; then
    echo "Ошибка: лог-файл не существует или недоступен для чтения: $log_file" >&2
    exit 1
fi
if [[ $keyword == *$'\n'* ]]; then
    echo "Ошибка: ключевое слово должно занимать одну строку." >&2
    exit 1
fi

matches_file="${log_file}.errors.txt"
count_file="${log_file}.count.txt"
status=0
grep -aF -- "$keyword" "$log_file" > "$matches_file" || status=$?
if [[ $status -gt 1 ]]; then
    echo "Ошибка чтения лог-файла." >&2
    exit "$status"
fi
count=$(awk 'END { print NR + 0 }' "$matches_file")
printf 'Количество строк с ключевым словом "%s": %s\n' "$keyword" "$count" \
    | tee "$count_file"
printf 'Найденные строки: %s\nРезультат подсчета: %s\n' "$matches_file" "$count_file"

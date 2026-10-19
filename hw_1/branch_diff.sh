#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Использование: $0 <репозиторий> <ветка_1> <ветка_2>" >&2
    exit 1
fi

repository=$1
branch_1=$2
branch_2=$3
command -v git >/dev/null || { echo "Ошибка: требуется Git." >&2; exit 1; }
for branch in "$branch_1" "$branch_2"; do
    if ! git check-ref-format "refs/heads/$branch" >/dev/null; then
        echo "Ошибка: некорректное имя ветки: $branch" >&2
        exit 1
    fi
done

temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
git init --bare --quiet "$temporary_directory/repository.git"
git -C "$temporary_directory/repository.git" fetch --quiet --no-tags --depth=1 -- \
    "$repository" \
    "refs/heads/$branch_1:refs/compare/first"
git -C "$temporary_directory/repository.git" fetch --quiet --no-tags --depth=1 -- \
    "$repository" \
    "refs/heads/$branch_2:refs/compare/second"

git -C "$temporary_directory/repository.git" diff --no-renames --name-status -z \
    refs/compare/first refs/compare/second > "$temporary_directory/changes"

added=0 deleted=0 modified=0 other=0 total=0
while IFS= read -r -d '' status && IFS= read -r -d '' filename; do
    case "$status" in
        A) added=$((added + 1)) ;;
        D) deleted=$((deleted + 1)) ;;
        M) modified=$((modified + 1)) ;;
        *) other=$((other + 1)) ;;
    esac
    total=$((total + 1))
    printf '%s\t%q\n' "$status" "$filename"
done < "$temporary_directory/changes" > "$temporary_directory/list"

safe_1=${branch_1//\//_}
safe_2=${branch_2//\//_}
report="diff_report_${safe_1}_vs_${safe_2}.txt"
{
    printf 'Отчет о различиях между ветками\n\n'
    printf '================================\n'
    printf 'Репозиторий:     %s\n' "$repository"
    printf 'Ветка 1:        %s\n' "$branch_1"
    printf 'Ветка 2:        %s\n' "$branch_2"
    printf 'Дата генерации: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '================================\n\nСПИСОК ИЗМЕНЕННЫХ ФАЙЛОВ:\n'
    if [[ $total -eq 0 ]]; then
        printf 'Различий нет.\n'
    else
        cat "$temporary_directory/list"
    fi
    printf '\nСТАТИСТИКА:\nВсего измененных файлов: %s\n' "$total"
    printf 'Добавлено (A): %s\nУдалено (D): %s\nИзменено (M): %s\n' \
        "$added" "$deleted" "$modified"
    printf 'Другие изменения (например, тип файла T): %s\n' "$other"
} > "$report"
printf 'Отчет сохранен: %s\n' "$report"

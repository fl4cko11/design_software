#!/usr/bin/env bash
# Сборка и публикация в Docker Hub, GHCR или другом Docker registry.
set -euo pipefail

usage() {
    echo "Использование: $0 <registry/namespace/image> <tag>" >&2
    echo "Пример: $0 ghcr.io/your-login/design-hw2 1.0" >&2
}

if [[ $# -ne 2 || -z $1 || -z $2 ]]; then
    usage
    exit 1
fi
repository=$1
tag=$2
if [[ $repository == -* || $repository != */* || $repository == *[[:space:]]* \
      || $repository == *@* || $repository == *://* \
      || ! $tag =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ]]; then
    usage
    echo "Ошибка: укажите имя образа с namespace и отдельный корректный тег." >&2
    exit 1
fi
command -v docker >/dev/null || { echo "Ошибка: требуется Docker." >&2; exit 1; }
docker info >/dev/null

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
image="$repository:$tag"
printf 'Сборка %s\n' "$image"
docker build --pull --target runtime --tag "$image" "$script_directory"
printf 'Публикация %s\n' "$image"
docker push "$image"
printf 'Готово. Образ: %s\n' "$image"

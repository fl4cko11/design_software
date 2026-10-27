# Отчет по лабораторной работе №2: Docker и Docker Compose

Цель работы — собрать образ приложения с разделением стадий сборки и запуска,
организовать взаимодействие контейнеров через Docker Compose и обеспечить
сохранение данных PostgreSQL.

Реализовано HTTP API на Python с эндпоинтами `/health` и `/notes`.
В состав приложения входят Nginx, HTTP API и PostgreSQL. Nginx принимает
HTTP-запросы и передает их приложению; приложение сохраняет заметки в БД.

Для сборки и запуска необходимы Docker Engine / Docker Desktop и Docker Compose
v2+. Все команды ниже выполняются из каталога `hw_2`.

## 1. Отдельный образ приложения

```bash
docker build -t design-hw2-app:1.0 .
docker run -d --name hw2-app -p 8080:8080 \
  -e APP_MESSAGE="Hello from my container!" design-hw2-app:1.0
curl -i http://localhost:8080/health
curl http://localhost:8080/
docker inspect --format '{{.State.Health.Status}}' hw2-app
docker exec hw2-app id
```

`/health` возвращает HTTP 200 и `{"status": "ok", "database": "disabled"}`.
Без настроек БД работают `/` и `/health`; `/notes` возвращает 503.
Docker healthcheck обновляется раз в 10 секунд, поэтому сначала статус `starting`.
`id` показывает UID/GID `10001`, а не root.

Остановить и удалить этот демонстрационный контейнер:

```bash
docker stop hw2-app
docker rm hw2-app
```

### Реализация Dockerfile

- `builder` устанавливает зависимость в `/opt/venv`.
- `runtime` копирует только окружение и два Python-файла приложения;
  файлы сборки и кеш pip в него не переносятся.
- Runtime использует `slim-bookworm`. Базовые образы закреплены полными тегами
  и digest, зависимость — версией и SHA-256. Поддержаны Linux amd64 и arm64.
- В Dockerfile есть `ENV`, `EXPOSE`, `USER`, `HEALTHCHECK` и `ENTRYPOINT`.
  Команды `HEALTHCHECK` и `ENTRYPOINT` записаны в exec-форме.
- `EXPOSE 8080` описывает порт; публикацию выполняет `docker run -p`.
- `.dockerignore` разрешает включать в контекст только файлы сборки приложения;
  `.env`, Git и документация в образ не попадают.

Фиксация версий и хешей обеспечивает использование определенных базовых образов
и зависимостей при повторной сборке. Для обновления компонентов необходимо
изменить версии, digest и хеши зависимостей. Сборки для разных архитектур
создают разные образы.

## 2. Стек Nginx → app → PostgreSQL

Создать локальный файл окружения:

```bash
cp .env.example .env
```

В `.env` обязательно заполнить `POSTGRES_PASSWORD` собственным паролем.
Можно сгенерировать его командой `openssl rand -hex 24`. Настоящий `.env`
игнорируется Git; в `.env.example` пароль пустой. Без пароля Compose не запустится.

```bash
docker compose config --quiet
docker compose up -d --build --wait
docker compose ps
curl -i http://localhost/health
curl http://localhost/
```

После первой сборки достаточно `docker compose up -d`.
Ответ `/health`: HTTP 200, `{"status": "ok", "database": "ok"}`.
В этом режиме healthcheck проверяет соединение с PostgreSQL запросом `SELECT 1`.

| Сервис | Сеть | Порт внутри контейнера | Публикация на хосте |
| --- | --- | --- | --- |
| nginx | frontend | 80 | 80 |
| app | frontend, backend | 8080 | Нет |
| db | backend | 5432 | Нет |

`backend` — внутренняя сеть. Nginx обращается к `app:8080`, приложение — к
`db:5432` через Docker DNS. `app` ждет здоровую БД, Nginx — здоровое приложение.
Файловая система app доступна только для чтения, capabilities сброшены,
повышение привилегий запрещено. Конфигурация Nginx монтируется только для чтения.

Поле `version: "3.8"` сохранено по условию. Современный Compose выводит
предупреждение об устаревшем поле; это не ошибка запуска.

### Проверка сохранения данных

Добавить запись и прочитать ее через Nginx:

```bash
curl -i -X POST http://localhost/notes \
  -H 'Content-Type: application/json' \
  -d '{"text":"Запись должна пережить перезапуск"}'
curl http://localhost/notes
```

POST возвращает HTTP 201. Поле `text` содержит от 1 до 1000 символов после
удаления пробелов по краям; GET возвращает последние 100 записей.
SQL-параметры передаются отдельно от запроса.

Пересоздать контейнеры, сохранив том:

```bash
docker compose down
docker compose up -d --wait
curl http://localhost/notes
```

Запись остается в PostgreSQL благодаря именованному тому `pgdata`.
`docker compose restart` тоже сохраняет данные. Не используйте `down -v`,
если данные нужны: эта команда удаляет том.

Проверить публикацию портов и логи:

```bash
docker compose ps
docker compose port nginx 80
docker compose port app 8080
docker compose port db 5432
docker compose logs --tail=50
```

Только первая команда `port` должна показать опубликованный порт. Для app и db
Compose сообщит, что порт не опубликован. Числа `8080/tcp` и `5432/tcp`
в колонке PORTS без стрелки `->` не означают публикацию на хосте.

Изменение `POSTGRES_PASSWORD` в `.env` не меняет пароль уже созданной БД:
переменные инициализации PostgreSQL применяются к пустому тому.

## 3. Сборка и публикация в registry

Скрипт `build_push.sh` собирает runtime-образ и выполняет `docker push`.
Он принимает имя образа с namespace и тег; работает из любого текущего каталога.
Перед запуском скрипта выполняется авторизация в выбранном registry.
Пароли и токены в скрипт не записываются.

Docker Hub (замените `your-login` своим логином):

```bash
docker login
./build_push.sh your-login/design-hw2 1.0
```

GitHub Container Registry:

```bash
docker login ghcr.io
./build_push.sh ghcr.io/your-login/design-hw2 1.0
```

Для GHCR необходим токен с правом публикации пакетов, который вводится в запросе
`docker login`. Скрипт останавливается при ошибке сборки или публикации.
Публикуется образ для архитектуры машины сборки, без автоматической сборки
multi-platform образа. Локальная сборка из исходников поддерживает amd64 и arm64.

Проверить опубликованный образ на совместимой машине:

```bash
docker pull your-login/design-hw2:1.0
docker run --rm -p 8080:8080 your-login/design-hw2:1.0
# В другом терминале:
curl -i http://localhost:8080/health
```

Значение `your-login` в примерах заменяется на namespace учетной записи registry.

## 4. Результаты проверки

Проверка выполнена в Docker Desktop на архитектуре arm64.

| Проверка | Результат |
| --- | --- |
| Сборка приложения через `docker build` | Образ успешно собран |
| Запуск через `docker run -p 8080:8080 -e APP_MESSAGE=...` | Приложение запущено, переменная окружения применена |
| `/health` отдельного контейнера | HTTP 200 |
| Запуск Compose-стека | Все три контейнера имеют статус `healthy` |
| `/health` через Nginx | HTTP 200, `database: ok` |
| Пользователь процесса приложения | UID/GID `10001`, non-root |
| Публикация портов | На хост опубликован только порт Nginx `80` |
| Создание и чтение заметки | POST — HTTP 201; запись доступна через GET |
| Сохранение данных после `docker compose down` и повторного запуска | Запись сохранена в томе `pgdata` |
| Передача пустой заметки | HTTP 400 |

Для `build_push.sh` проверены аргументы, порядок вызовов `build` и `push`, запуск
из другого каталога и остановка при ошибке сборки. В этих проверках команды Docker
подменялись тестовой командой; фактическая публикация в registry не выполнялась.

После проверки тестовые контейнеры, сети, том и образы удалены.

### Скриншоты

Скриншоты реального запуска находятся в `screenshots/`:

- [Статус контейнеров и HTTP 200](screenshots/containers.jpg) — снимок браузерного
  отчета с фактическим выводом команд проверки.
- [Ответ приложения через Nginx](screenshots/health.jpg) — снимок `/health` в браузере.
- [Исходный вывод команд](screenshots/verification.txt) — дата проверки, статусы,
  опубликованные порты, UID приложения и HTTP-ответ.

## 5. Состав проекта

| Файл или каталог | Назначение |
| --- | --- |
| `app.py` | HTTP API и взаимодействие с PostgreSQL |
| `healthcheck.py` | Проверка доступности `/health` |
| `requirements.txt` | Версия зависимости и хеши wheel-файлов |
| `Dockerfile` | Стадии `builder` и `runtime` |
| `docker-compose.yml` | Описание сервисов, сетей и тома |
| `nginx/default.conf` | Конфигурация reverse proxy |
| `.env.example` | Шаблон переменных окружения |
| `.gitignore`, `.dockerignore` | Исключение локальных настроек и лишних файлов |
| `build_push.sh` | Сборка и публикация образа в registry |
| `screenshots/` | Скриншоты и вывод команд проверки |

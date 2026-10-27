# ДЗ №2: Docker и Docker Compose

Небольшой Python HTTP API с PostgreSQL. Python выбран как разрешенная в условии
альтернатива Spring Boot. Нужны Docker Engine / Docker Desktop и Docker Compose v2+.
Команды ниже выполняются из каталога `hw_2`.

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

### Как устроена сборка

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

Образы и зависимости намеренно закреплены. При обновлении версии нужно обновлять
ее digest/хеши и повторять проверки. Это фиксация входных данных сборки, а не
обещание побитово одинакового результата на разных архитектурах.

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
В этом режиме healthcheck действительно проверяет соединение с PostgreSQL.

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

## Кратко для защиты

- **Зачем multi-stage?** Подготовка зависимостей отделена от запуска;
  в runtime копируется готовое окружение.
- **Зачем non-root?** Приложение работает с ограниченными правами внутри контейнера.
- **Зачем digest?** Тег может обновиться; digest фиксирует конкретное содержимое образа.
- **Зачем healthcheck?** Проверяет готовность HTTP API, а в Compose — и доступ к БД.
- **Зачем две сети?** Nginx имеет доступ к приложению, БД находится только в backend.
- **Почему БД доступна без `ports`?** Контейнеры общей сети используют внутренний порт.
- **Зачем volume?** Данные БД живут отдельно от жизненного цикла контейнера.
- **Где секреты?** В локальном `.env`; он не коммитится и не копируется в образ.
- **Это production-сервер?** Это учебный API на стандартной библиотеке Python.
  Для production нужны подходящий сервер, аутентификация и ограничения нагрузки.

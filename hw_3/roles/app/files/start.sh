#!/bin/sh
set -eu

# Конфигурация создается Ansible и доступна на запись только root.
set -a
. /etc/hw3-app/app.env
set +a

cd /opt/hw3-app
exec /usr/bin/python3 -u /opt/hw3-app/app.py

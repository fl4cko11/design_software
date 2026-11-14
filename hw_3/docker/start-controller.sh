#!/bin/sh
set -eu
install -d -m 0700 /root/.ssh
if [ ! -s /root/.ssh/id_ed25519 ]; then
    ssh-keygen -q -t ed25519 -N '' -f /root/.ssh/id_ed25519
fi
# Только открытый ключ передается управляемым контейнерам.
install -m 0644 /root/.ssh/id_ed25519.pub /keys/controller.pub.tmp
mv /keys/controller.pub.tmp /keys/controller.pub
exec sleep infinity

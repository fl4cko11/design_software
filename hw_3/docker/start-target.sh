#!/bin/sh
set -eu
install -d -m 0700 /root/.ssh
install -m 0600 /keys/controller.pub /root/.ssh/authorized_keys
mkdir -p /run/sshd
ssh-keygen -A

# При перезапуске контейнера поднимаем уже установленные Ansible службы.
for service in supervisor nginx; do
    if [ -x "/etc/init.d/$service" ]; then
        "/etc/init.d/$service" start
    fi
done

exec /usr/sbin/sshd -D -e -o PermitRootLogin=prohibit-password \
    -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no \
    -o AllowTcpForwarding=no -o X11Forwarding=no

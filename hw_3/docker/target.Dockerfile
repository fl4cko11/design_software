FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /etc/ssh/ssh_host_*_key*
COPY docker/start-target.sh /usr/local/bin/start-target
HEALTHCHECK --interval=2s --timeout=2s --retries=15 CMD test -s /run/sshd.pid && kill -0 "$(cat /run/sshd.pid)"
ENTRYPOINT ["/bin/sh", "/usr/local/bin/start-target"]

FROM python:3.13.18-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir ansible-core==2.19.0
COPY docker/start-controller.sh /usr/local/bin/start-controller
WORKDIR /lab
HEALTHCHECK --interval=2s --timeout=2s --retries=15 CMD test -s /keys/controller.pub && cmp -s /root/.ssh/id_ed25519.pub /keys/controller.pub
ENTRYPOINT ["/bin/sh", "/usr/local/bin/start-controller"]

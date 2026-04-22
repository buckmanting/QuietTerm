FROM debian:12.11-slim@sha256:b1a741487078b369e78119849663d7f1a5341ef2768798f7b7406c4240f86aef

ARG DEBIAN_SNAPSHOT=20250811T000000Z

RUN rm -f /etc/apt/sources.list.d/debian.sources \
    && printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/%s bookworm main\n' "$DEBIAN_SNAPSHOT" > /etc/apt/sources.list \
    && printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/%s bookworm-updates main\n' "$DEBIAN_SNAPSHOT" >> /etc/apt/sources.list \
    && printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/%s bookworm-security main\n' "$DEBIAN_SNAPSHOT" >> /etc/apt/sources.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        netcat-openbsd \
        openssh-server \
        passwd \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash quiet \
    && echo 'quiet:quiet-password' | chpasswd \
    && mkdir -p /var/run/sshd /home/quiet/.ssh /fixture \
    && chown -R quiet:quiet /home/quiet/.ssh \
    && chmod 700 /home/quiet/.ssh

COPY entrypoint.sh /usr/local/bin/fixture-entrypoint.sh
RUN chmod 755 /usr/local/bin/fixture-entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/fixture-entrypoint.sh"]

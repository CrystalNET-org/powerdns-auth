FROM harbor.crystalnet.org/dockerhub-proxy/alpine:3.19 AS builder

# renovate: datasource=github-tags depName=PowerDNS/pdns extractVersion=^auth-(?<version>.*)$ versioning=semver
ENV POWERDNS_VERSION=4.8.4

RUN apk --update --no-cache add \
    bash \
    libpq \
    libstdc++ \
    libgcc \
    mariadb-client \
    mariadb-connector-c \
    lua-dev \
    curl-dev \
    g++ \
    make \
    mariadb-dev \
    postgresql-dev \
    curl \
    boost-dev \
    mariadb-connector-c-dev \
    libsodium-dev

RUN curl -sSL https://downloads.powerdns.com/releases/pdns-$POWERDNS_VERSION.tar.bz2 | tar xj -C /tmp && \
    cd /tmp/pdns-$POWERDNS_VERSION && \
    ./configure \
        --prefix="/opt/pdns" \
        --exec-prefix="/opt/pdns" \
        --sysconfdir="/etc/pdns" \
        --disable-lua-records \
        --without-tools \
        --without-sqlite3 \
        --without-systemd \
        --with-libsodium \
        --with-socketdir=/tmp \
        --with-modules="bind gmysql gpgsql pipe" && \
    make -j8 && make install-strip && \
    rm /opt/pdns/share -r && \
    ls /opt/*
    
FROM harbor.crystalnet.org/dockerhub-proxy/alpine:3.19
LABEL author="Lukas Wingerberg"
LABEL author_email="h@xx0r.eu"

RUN apk --update --no-cache add \
    bash \
    libpq \
    libstdc++ \
    mariadb-connector-c \
    lua-dev \
    libsodium \
    libcurl

RUN addgroup -S pdns 2>/dev/null && \
    adduser -S -D -H -h /var/empty -s /bin/false -G pdns -g pdns pdns 2>/dev/null

COPY --from=builder /opt /opt
ADD rootfs/ /

EXPOSE 10353/tcp 10353/udp

ENTRYPOINT ["/entrypoint.sh"]

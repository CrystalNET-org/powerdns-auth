FROM harbor.crystalnet.org/dockerhub-proxy/alpine:3.19 AS builder

# renovate: datasource=github-tags depName=PowerDNS/pdns extractVersion=^auth-(?<version>.*)$ versioning=semver
ENV POWERDNS_VERSION=4.8.4

RUN apk --update --no-cache add \
    bash \
    libpq \
    sqlite-libs \
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
    sqlite-dev \
    curl \
    boost-dev \
    mariadb-connector-c-dev \
    libsodium-dev \
    bash

RUN curl -sSL https://downloads.powerdns.com/releases/pdns-$POWERDNS_VERSION.tar.bz2 | tar xj -C /tmp && \
    cd /tmp/pdns-$POWERDNS_VERSION && \
    ./configure \
        --prefix="/opt/pdns" \
        --exec-prefix="/opt/pdns" \
        --sysconfdir="/etc/pdns" \
        --enable-static \
        --enable-tools \
        --with-libsodium \
        --with-sqlite3 \
        --with-socketdir=/tmp \
        --with-modules="bind gmysql gpgsql gsqlite3 pipe" && \
    make -j8 && make install-strip && \
    ls /opt/*
    
RUN cp /usr/lib/libboost_program_options.so* /tmp && \
    apk add boost-libs && \
    mv /tmp/lib* /usr/lib/ && \
    rm -rf /tmp/pdns-$POWERDNS_VERSION /var/cache/apk/*

FROM harbor.crystalnet.org/dockerhub-proxy/alpine:3.19
LABEL author="Lukas Wingerberg"
LABEL author_email="h@xx0r.eu"

RUN apk --update --no-cache add \
    bash \
    libpq \
    sqlite-libs \
    mariadb-connector-c \
    lua-dev \
    libsodium \
    curl

RUN addgroup -S pdns 2>/dev/null && \
    adduser -S -D -H -h /var/empty -s /bin/false -G pdns -g pdns pdns 2>/dev/null

COPY --from=builder /opt /opt
ADD rootfs/ /

EXPOSE 53/tcp 53/udp

ENTRYPOINT ["/entrypoint.sh"]

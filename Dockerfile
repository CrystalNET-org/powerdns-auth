FROM alpine:3.17
LABEL author="Lukas Wingerberg"
LABEL author_email="h@xx0r.eu"

# renovate: datasource=github-tags depName=PowerDNS/pdns extractVersion=^auth-(?<version>.*)$ versioning=semver
ENV POWERDNS_VERSION=4.7.3
ENV MYSQL_DEFAULT_AUTOCONF=true \
    MYSQL_DEFAULT_HOST="mysql" \
    MYSQL_DEFAULT_PORT="3306" \
    MYSQL_DEFAULT_USER="root" \
    MYSQL_DEFAULT_PASS="root" \
    MYSQL_DEFAULT_DB="pdns"

RUN mkdir -p /etc/pdns/conf.d

RUN addgroup -S pdns 2>/dev/null && \
    adduser -S -D -H -h /var/empty -s /bin/false -G pdns -g pdns pdns 2>/dev/null

RUN apk --update add bash libpq sqlite-libs libstdc++ libgcc mariadb-client mariadb-connector-c lua-dev curl-dev && \
    apk add --virtual build-deps \
      g++ make mariadb-dev postgresql-dev sqlite-dev curl boost-dev mariadb-connector-c-dev

RUN curl -sSL https://downloads.powerdns.com/releases/pdns-$POWERDNS_VERSION.tar.bz2 | tar xj -C /tmp && \
    cd /tmp/pdns-$POWERDNS_VERSION && \
    ./configure --prefix="" --exec-prefix=/usr --sysconfdir=/etc/pdns \
      --with-modules="bind gmysql gpgsql gsqlite3" && \
    make && make install-strip 
    
RUN cp /usr/lib/libboost_program_options.so* /tmp && \
    apk del --purge build-deps && \
    apk add boost-libs && \
    mv /tmp/lib* /usr/lib/ && \
    rm -rf /tmp/pdns-$POWERDNS_VERSION /var/cache/apk/*

ADD rootfs/ /

EXPOSE 53/tcp 53/udp

ENTRYPOINT ["/entrypoint.sh"]

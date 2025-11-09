# PowerDNS Docker Image

Welcome to the PowerDNS Docker image, a containerized instance of the authoritative DNS server.
This image is designed to be run rootless and with a readonly rootfs. Generally, security has been taken seriously and no writes should occur.

## Getting Started

### Prerequisites

* Docker installed on your system.

### Quick Start

Pull the PowerDNS Docker image:

```
docker pull ghcr.io/crystalnet-org/powerdns-auth:<tag>
```

Run the PowerDNS container with default settings (no database backend):

```
docker run -d -p 53:10353/tcp -p 53:10353/udp ghcr.io/crystalnet-org/powerdns-auth:<tag>
```

## Configuration

The PowerDNS container is customized using environment variables.

### Mapping Parameters to Environment Variables

The environment variables are derived from the PowerDNS settings by converting them to uppercase, prepending `PDNS_`, and replacing hyphens with underscores. For example, a PowerDNS setting like `api-key` becomes the environment variable `PDNS_API_KEY`.

### Example

To configure PowerDNS Server to launch the API, you can set the corresponding environment variables:

```
export PDNS_LAUNCH=gmysql
export PDNS_API=yes
export PDNS_API_KEY=your-api-key
export PDNS_API_PORT=8081
```

These environment variables will be translated into the following PowerDNS command line parameters on startup:

```
--launch=gmysql
--api=yes
--api-key=your-api-key
--api-port=8081
```

## Database Configuration

This image supports `gmysql` (MySQL/MariaDB) and `gpgsql` (PostgreSQL) backends. The backend is automatically detected at startup based on which set of environment variables you provide.

**Note:** You must not set variables for both `PDNS_GMYSQL_HOST` and `PDNS_GPGSQL_HOST` at the same time.

### MySQL (`gmysql`)

Use the following environment variables to configure a MySQL backend:

```
# Required
PDNS_GMYSQL_HOST=my-mysql-server
PDNS_GMYSQL_PORT=3306
PDNS_GMYSQL_USER=myuser
PDNS_GMYSQL_PASSWORD=mypassword
PDNS_GMYSQL_DBNAME=mydatabase
# Optional
PDNS_GMYSQL_DNSSEC=yes
# ... any other pdns-gmysql-* setting
```

### PostgreSQL (`gpgsql`)

Use the following environment variables to configure a PostgreSQL backend:

```
# Required
PDNS_GPGSQL_HOST=my-pgsql-server
PDNS_GPGSQL_PORT=5432
PDNS_GPGSQL_USER=myuser
PDNS_GPGSQL_PASSWORD=mypassword
PDNS_GPGSQL_DBNAME=mydatabase
# Optional
PDNS_GPGSQL_DNSSEC=yes
# ... any other pdns-gpgsql-* setting
```

### Example Usage (PostgreSQL)

```
docker run -d -p 53:10353/tcp -p 53:10353/udp \
  -e PDNS_LAUNCH=gpgsql \
  -e PDNS_GPGSQL_HOST=my-pgsql-server \
  -e PDNS_GPGSQL_PORT=5432 \
  -e PDNS_GPGSQL_USER=myuser \
  -e PDNS_GPGSQL_PASSWORD=mypassword \
  -e PDNS_GPGSQL_DBNAME=mydatabase \
  crystalnetorg/powerdns-auth:<tag>
```

## Schema Management

The entrypoint script validates the database schema against a blessed schema file located inside the container.

* **MySQL:** If a schema difference is detected, the script will attempt to synchronize the database using `pt-table-sync`. This behavior is still a work-in-progress.

* **PostgreSQL:** If a schema difference is detected, the container will log an error with the diff and **fail to start**. Automatic schema migration is not supported for PostgreSQL. You must apply migrations manually or ensure the schema file in the image (`/etc/pdns/pgsql_schema.sql`) matches your database.

## Health & Readiness Checks

The image includes two scripts for container orchestration platforms like Kubernetes and Docker Compose.

### Liveness Probe

* **Script:** `/container/docker-liveness.sh`

* **Purpose:** Checks if the `pdns_server` process is running. This is a lightweight check to see if the container is "alive."

* **K8s:** Use this for your `livenessProbe`.

### Readiness Probe

* **Script:** `/container/docker-readiness.sh`

* **Purpose:** Performs a comprehensive check to see if the container is ready to accept traffic. It verifies:

  1. Database connectivity (MySQL or PostgreSQL).

  2. PowerDNS API responsiveness (requires `PDNS_API=yes` and `PDNS_API_KEY` to be set).

* **K8s:** Use this for your `readinessProbe`.

### Example `docker-compose.yml` Healthcheck

```
version: '3.8'
services:
  powerdns:
    image: ghcr.io/crystalnet-org/powerdns-auth:<tag>
    ports:
      - "53:10353/udp"
      - "53:10353/tcp"
      - "8081:8081/tcp"
    environment:
      - PDNS_LAUNCH=gmysql
      - PDNS_API=yes
      - PDNS_API_KEY=my-super-secret-key
      - PDNS_GMYSQL_HOST=db
      - PDNS_GMYSQL_USER=pdns
      - PDNS_GMYSQL_PASSWORD=pdns
      - PDNS_GMYSQL_DBNAME=pdns
    # Use the readiness check as the default Docker healthcheck
    healthcheck:
      test: ["CMD", "/container/docker-readiness.sh"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
    # ... depends_on: [db] ...
```

## Exposed Ports

The PowerDNS container exposes the following ports by default:

* TCP: 10353

* UDP: 10353

If you enable the API, you will also need to map the API port (e.g., `8081/tcp`).

## Additional Information

For a comprehensive list of available PowerDNS settings and their descriptions, please refer to the [PowerDNS Authoritative Server Settings documentation](https://doc.powerdns.com/authoritative/settings.html).

Feel free to explore and contribute to this PowerDNS Docker image on [GitHub](https://github.com/CrystalNET-org/powerdns-auth).
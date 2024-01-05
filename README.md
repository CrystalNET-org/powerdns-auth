# PowerDNS Docker Image

Welcome to the PowerDNS Docker image, a containerized instance of the authoritative DNS server. This image is designed to simplify the deployment of PowerDNS while providing flexibility for different database backends.

## Getting Started

### Prerequisites
- Docker installed on your system.

### Quick Start
Pull the PowerDNS Docker image:

```bash
docker pull CrystalNET-org/powerdns-auth:<tag>
```

Run the PowerDNS container with default settings:

```bash
docker run -d -p 53:10353/tcp -p 53:10353/udp CrystalNET-org/powerdns-auth:<tag>
```

## Configuration

The PowerDNS container can be customized using environment variables

### Mapping Parameters to Environment Variables

The environment variables are derived from the PowerDNS settings by converting them to uppercase and replacing underscores with hyphens. For example, a PowerDNS setting like `launch` becomes the environment variable `PDNS_LAUNCH`.

### Example

To configure PowerDNS Server to launch the API with specific settings, you can set the corresponding environment variables:

```bash
export PDNS_LAUNCH=bind,gmysql
export PDNS_API_KEY=your-api-key
export PDNS_API_PORT=8081
```

These environment variables will be translated into the following PowerDNS command line parameters on startup:

```bash
--launch=bind,gmysql
--api-key=your-api-key
--api-port=8081
```

### Example Usage
Run PowerDNS with a specific MySQL configuration:

```bash
docker run -d -p 53:10353/tcp -p 53:10353/udp \
  -e PDNS_LAUNCH=gmysql \
  -e PDNS_GMYSQL_HOST=my-mysql-server \
  -e PDNS_GMYSQL_PORT=3307 \
  -e PDNS_GMYSQL_USER=myuser \
  -e PDNS_GMYSQL_PASSWORD=mypassword \
  -e PDNS_GMYSQL_DBNAME=mydatabase \
  CrystalNET-org/powerdns-auth:<tag>
```

Adjust the MySQL environment variables based on your database setup.

## Exposed Ports

The PowerDNS container exposes the following ports by default:
- TCP: 10353
- UDP: 10353

## Additional Information

For a comprehensive list of available PowerDNS settings and their descriptions, please refer to the [PowerDNS Authoritative Server Settings documentation](https://doc.powerdns.com/authoritative/settings.html).

For additional configurations and details, refer to the [PowerDNS documentation](https://doc.powerdns.com/). Customize the Dockerfile and configurations to suit your specific requirements.

Feel free to explore and contribute to this PowerDNS Docker image on [GitHub](https://github.com/your-username/powerdns-docker).

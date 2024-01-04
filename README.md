# PowerDNS Docker Image

Welcome to the PowerDNS Docker image, a containerized instance of the authoritative DNS server. This image is designed to simplify the deployment of PowerDNS while providing flexibility for different database backends.

## Getting Started

### Prerequisites
- Docker installed on your system.

### Quick Start
Pull the PowerDNS Docker image:

```bash
docker pull <dockerhub-username>/powerdns:<tag>
```

Run the PowerDNS container with default settings:

```bash
docker run -d -p 53:53/tcp -p 53:53/udp <dockerhub-username>/powerdns:<tag>
```

## Configuration

### Environment Variables
The PowerDNS container can be customized using the following environment variables:

- **`MYSQL_DEFAULT_AUTOCONF`**: Enable automatic MySQL configuration (default is true).
- **`MYSQL_DEFAULT_HOST`**: MySQL server host (default is "mysql").
- **`MYSQL_DEFAULT_PORT`**: MySQL server port (default is "3306").
- **`MYSQL_DEFAULT_USER`**: MySQL server user (default is "root").
- **`MYSQL_DEFAULT_PASS`**: MySQL server password (default is "root").
- **`MYSQL_DEFAULT_DB`**: MySQL database name (default is "pdns").

### Example Usage
Run PowerDNS with a specific MySQL configuration:

```bash
docker run -d -p 53:53/tcp -p 53:53/udp \
  -e MYSQL_DEFAULT_HOST=my-mysql-server \
  -e MYSQL_DEFAULT_PORT=3307 \
  -e MYSQL_DEFAULT_USER=myuser \
  -e MYSQL_DEFAULT_PASS=mypassword \
  -e MYSQL_DEFAULT_DB=mydatabase \
  <dockerhub-username>/powerdns:<tag>
```

Adjust the MySQL environment variables based on your database setup.

## Exposed Ports
The PowerDNS container exposes the following ports:
- TCP: 53
- UDP: 53

## Additional Information
For additional configurations and details, refer to the [PowerDNS documentation](https://doc.powerdns.com/). Customize the Dockerfile and configurations to suit your specific requirements.

Feel free to explore and contribute to this PowerDNS Docker image on [GitHub](https://github.com/your-username/powerdns-docker).

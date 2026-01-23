# Ansible Playbooks for Observability Stack

Automate the deployment of the OpenTelemetry observability stack on Linux servers using Docker Compose.

## Features

- Automated Docker installation
- Single-node or scalable deployment
- Systemd service integration
- Automated backups via cron
- Health checks

## Prerequisites

1. **Control Machine** (where you run Ansible):
   - Ansible 2.10+
   - SSH access to target servers

2. **Target Servers**:
   - Ubuntu 20.04/22.04 or Debian 11+
   - SSH access with sudo privileges
   - Minimum 8GB RAM (16GB for scalable)
   - 50GB disk space

## Quick Start

```bash
# 1. Install Ansible (on your control machine)
pip install ansible

# 2. Configure inventory
cp inventory.example inventory
# Edit inventory with your server IPs

# 3. Test connectivity
ansible -i inventory all -m ping

# 4. Deploy (single-node)
ansible-playbook -i inventory playbook.yml

# 5. Deploy (scalable with Kafka)
ansible-playbook -i inventory playbook.yml -e deployment_type=scalable
```

## Inventory Configuration

Edit `inventory` file:

```ini
[observability]
# Single server
server1 ansible_host=192.168.1.100

[observability:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_rsa
grafana_admin_password=your-secure-password
deployment_type=single
```

## Playbook Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `deployment_type` | `single` | Deployment type (`single` or `scalable`) |
| `install_dir` | `/opt/observability` | Installation directory |
| `grafana_admin_password` | `admin` | Grafana admin password |
| `otel_collector_version` | `0.91.0` | OTel Collector version |
| `prometheus_retention` | `7d` | Prometheus data retention |
| `otel_gateway_replicas` | `2` | Gateway replicas (scalable mode) |
| `otel_processor_replicas` | `2` | Processor replicas (scalable mode) |

## Usage Examples

### Single Node Deployment

```bash
ansible-playbook -i inventory playbook.yml
```

### Scalable Deployment with Custom Settings

```bash
ansible-playbook -i inventory playbook.yml \
  -e deployment_type=scalable \
  -e otel_gateway_replicas=3 \
  -e otel_processor_replicas=3 \
  -e grafana_admin_password=MySecurePass123
```

### Dry Run (Check Mode)

```bash
ansible-playbook -i inventory playbook.yml --check --diff
```

### Deploy to Specific Host

```bash
ansible-playbook -i inventory playbook.yml --limit server1
```

## Directory Structure After Deployment

```
/opt/observability/
├── docker-compose.yaml      # Main compose file
├── .env                     # Environment variables
├── otel-collector.yaml      # OTel config (single mode)
├── otel-gateway.yaml        # Gateway config (scalable mode)
├── otel-processor.yaml      # Processor config (scalable mode)
├── haproxy.cfg             # Load balancer (scalable mode)
├── tempo.yaml              # Tempo config
├── mimir.yaml              # Mimir config
├── loki.yaml               # Loki config
├── prometheus.yml          # Prometheus config
├── grafana/
│   └── provisioning/
│       ├── datasources/
│       └── dashboards/
├── prometheus/
│   └── rules/
├── data/                   # Persistent data
├── logs/                   # Log files
├── backups/               # Backup storage
├── backup.sh              # Backup script
├── restore.sh             # Restore script
└── health-check.sh        # Health check script
```

## Management Commands

After deployment, SSH to your server:

```bash
# Check status
cd /opt/observability
docker compose ps

# View logs
docker compose logs -f

# Restart stack
systemctl restart observability

# Stop stack
systemctl stop observability

# Start stack
systemctl start observability

# Run health check
./health-check.sh

# Manual backup
./backup.sh
```

## Scaling (Scalable Mode)

```bash
# Scale gateways
cd /opt/observability
docker compose up -d --scale otel-gateway=5

# Scale processors
docker compose up -d --scale otel-processor=5
```

## Backup and Restore

Automated backups run daily at 2 AM. Manual operations:

```bash
# Manual backup
/opt/observability/backup.sh

# Restore from backup
/opt/observability/restore.sh /opt/observability/backups/20240115_020000
```

## Troubleshooting

### Cannot Connect to Server

```bash
# Test SSH connectivity
ssh -i ~/.ssh/id_rsa ubuntu@192.168.1.100

# Test Ansible connectivity
ansible -i inventory all -m ping -vvv
```

### Docker Not Starting

```bash
# Check Docker status
systemctl status docker

# View Docker logs
journalctl -u docker -f
```

### Stack Not Starting

```bash
# Check compose status
cd /opt/observability
docker compose ps
docker compose logs

# Check systemd service
systemctl status observability
journalctl -u observability -f
```

### Port Already in Use

```bash
# Check what's using the port
sudo lsof -i :3000
sudo netstat -tlnp | grep 3000
```

## Security Recommendations

1. **Change default passwords** - Set `grafana_admin_password` to a strong value
2. **Use SSH keys** - Don't use password authentication
3. **Firewall rules** - Restrict access to necessary ports only
4. **HTTPS** - Set up a reverse proxy with TLS for production
5. **Network isolation** - Use private networks for internal communication

## Files

| File | Description |
|------|-------------|
| `playbook.yml` | Main deployment playbook |
| `inventory.example` | Example inventory file |
| `templates/env.j2` | Environment file template |
| `README.md` | This documentation |

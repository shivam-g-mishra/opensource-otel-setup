#!/bin/bash
# =============================================================================
# Backup Script for Observability Stack
# =============================================================================
#
# Creates compressed backups of all Docker volumes
# Run via cron: 0 2 * * * /opt/otel-stack/scripts/backup.sh
#
# Environment Variables:
#   BACKUP_DIR      - Backup destination (default: ./backups)
#   RETENTION_DAYS  - Days to keep backups (default: 7)
#
# Usage:
#   ./backup.sh                    # Default backup
#   BACKUP_DIR=/mnt/nfs ./backup.sh  # Custom location

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Create backup directory
mkdir -p "$BACKUP_PATH"
log_info "Starting backup to ${BACKUP_PATH}..."

# List of volumes to backup
VOLUMES=(
  "prometheus-data"
  "grafana-data"
  "loki-data"
  "jaeger-data"
  "otel-storage"
  "kafka-data"
  "tempo-data"
  "mimir-data"
)

# Backup each volume
TOTAL_SIZE=0
for volume in "${VOLUMES[@]}"; do
  if docker volume inspect "$volume" &>/dev/null; then
    log_info "Backing up ${volume}..."
    docker run --rm \
      -v "${volume}:/source:ro" \
      -v "${BACKUP_PATH}:/backup" \
      alpine tar czf "/backup/${volume}.tar.gz" -C /source .
    
    SIZE=$(du -sh "${BACKUP_PATH}/${volume}.tar.gz" 2>/dev/null | cut -f1)
    log_info "  ${volume}: ${SIZE}"
  else
    log_warn "Volume ${volume} not found, skipping..."
  fi
done

# Backup configuration files
log_info "Backing up configuration files..."
CONFIG_FILES=(
  "docker-compose.yml"
  "docker-compose-scalable.yaml"
  "otel-collector.yaml"
  "otel-gateway.yaml"
  "otel-processor.yaml"
  "prometheus.yml"
  "loki.yaml"
  "haproxy.cfg"
)

mkdir -p "${BACKUP_PATH}/configs"
for file in "${CONFIG_FILES[@]}"; do
  if [[ -f "$file" ]]; then
    cp "$file" "${BACKUP_PATH}/configs/"
  fi
done

# Also backup any grafana provisioning
if [[ -d "grafana" ]]; then
  cp -r grafana "${BACKUP_PATH}/configs/"
fi

tar czf "${BACKUP_PATH}/configs.tar.gz" -C "${BACKUP_PATH}" configs
rm -rf "${BACKUP_PATH}/configs"

# Calculate total backup size
BACKUP_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
log_info "Backup complete: ${BACKUP_PATH} (${BACKUP_SIZE})"

# Create a manifest
cat > "${BACKUP_PATH}/manifest.txt" << EOF
Backup Manifest
===============
Timestamp: ${TIMESTAMP}
Date: $(date)
Host: $(hostname)
Total Size: ${BACKUP_SIZE}

Volumes:
$(for v in "${VOLUMES[@]}"; do echo "  - $v"; done)

Configuration Files:
$(for f in "${CONFIG_FILES[@]}"; do echo "  - $f"; done)
EOF

# Clean up old backups
if [[ -d "$BACKUP_DIR" ]]; then
  log_info "Cleaning backups older than ${RETENTION_DAYS} days..."
  DELETED=$(find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -print)
  if [[ -n "$DELETED" ]]; then
    echo "$DELETED" | while read -r dir; do
      log_info "  Deleting: $dir"
      rm -rf "$dir"
    done
  else
    log_info "  No old backups to delete"
  fi
fi

# Summary
log_info "========================================"
log_info "Backup Summary"
log_info "========================================"
log_info "Location: ${BACKUP_PATH}"
log_info "Size: ${BACKUP_SIZE}"
log_info "Retention: ${RETENTION_DAYS} days"
log_info "Backup completed successfully!"

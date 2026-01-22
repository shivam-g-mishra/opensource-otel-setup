#!/bin/bash
# =============================================================================
# Backup Script for OpenTelemetry Stack
# =============================================================================
# Creates compressed backups of all data volumes and configurations.
#
# Usage:
#   ./scripts/backup.sh                    # Backup to default location
#   BACKUP_DIR=/custom/path ./scripts/backup.sh  # Custom backup location
#
# Environment Variables:
#   BACKUP_DIR       - Backup destination (default: ./backups)
#   RETENTION_DAYS   - Days to keep old backups (default: 7)
# =============================================================================

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BACKUP_DIR:-${PROJECT_DIR}/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cd "$PROJECT_DIR"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  OpenTelemetry Stack Backup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Create backup directory
mkdir -p "$BACKUP_PATH"

echo -e "${YELLOW}Backup location: ${BACKUP_PATH}${NC}"
echo ""

# Get list of volumes
VOLUMES=$(docker volume ls --filter "name=opensource-otel-setup" --format "{{.Name}}" 2>/dev/null || \
          docker volume ls --filter "name=otel" --format "{{.Name}}" 2>/dev/null || \
          echo "prometheus-data grafana-data loki-data jaeger-data otel-collector-data")

# Backup each volume
echo -e "${BLUE}Backing up volumes...${NC}"
for volume in $VOLUMES; do
    # Extract short name
    short_name=$(echo "$volume" | sed 's/.*_//')
    
    if docker volume inspect "$volume" > /dev/null 2>&1; then
        echo -n "  Backing up ${short_name}... "
        docker run --rm \
            -v "${volume}:/source:ro" \
            -v "${BACKUP_PATH}:/backup" \
            alpine tar czf "/backup/${short_name}.tar.gz" -C /source . 2>/dev/null
        
        size=$(ls -lh "${BACKUP_PATH}/${short_name}.tar.gz" | awk '{print $5}')
        echo -e "${GREEN}done${NC} (${size})"
    else
        echo -e "  ${YELLOW}Skipping ${short_name} (not found)${NC}"
    fi
done
echo ""

# Backup configurations
echo -e "${BLUE}Backing up configurations...${NC}"
tar czf "${BACKUP_PATH}/configs.tar.gz" \
    docker-compose.yml \
    otel-collector-config.yaml \
    prometheus/ \
    loki/ \
    grafana/provisioning/ \
    .env 2>/dev/null || \
tar czf "${BACKUP_PATH}/configs.tar.gz" \
    docker-compose.yml \
    otel-collector-config.yaml \
    prometheus/ \
    loki/ \
    grafana/provisioning/ 2>/dev/null

config_size=$(ls -lh "${BACKUP_PATH}/configs.tar.gz" | awk '{print $5}')
echo -e "  Configurations: ${GREEN}done${NC} (${config_size})"
echo ""

# Create backup manifest
echo -e "${BLUE}Creating backup manifest...${NC}"
cat > "${BACKUP_PATH}/manifest.json" << EOF
{
  "timestamp": "${TIMESTAMP}",
  "date": "$(date -Iseconds)",
  "version": "1.0",
  "volumes": [$(echo $VOLUMES | tr ' ' '\n' | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')],
  "host": "$(hostname)",
  "docker_version": "$(docker --version | cut -d' ' -f3 | tr -d ',')"
}
EOF
echo -e "  Manifest: ${GREEN}done${NC}"
echo ""

# Calculate total backup size
BACKUP_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
echo -e "${GREEN}✓ Backup complete: ${BACKUP_PATH}${NC}"
echo -e "  Total size: ${BACKUP_SIZE}"
echo ""

# Clean old backups
if [ "$RETENTION_DAYS" -gt 0 ]; then
    echo -e "${BLUE}Cleaning backups older than ${RETENTION_DAYS} days...${NC}"
    old_backups=$(find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +${RETENTION_DAYS} 2>/dev/null | wc -l)
    if [ "$old_backups" -gt 0 ]; then
        find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} \;
        echo -e "  Removed ${old_backups} old backup(s)"
    else
        echo -e "  No old backups to remove"
    fi
fi

echo ""
echo -e "${GREEN}Backup finished successfully!${NC}"

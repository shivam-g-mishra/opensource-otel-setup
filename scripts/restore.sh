#!/bin/bash
# =============================================================================
# Restore Script for OpenTelemetry Stack
# =============================================================================
# Restores data from a backup created by backup.sh
#
# Usage:
#   ./scripts/restore.sh <backup_path>
#   ./scripts/restore.sh ./backups/20260122_020000
#
# Options:
#   --volumes-only    Only restore volumes, not configs
#   --configs-only    Only restore configs, not volumes
#   --force           Skip confirmation prompt
# =============================================================================

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
BACKUP_PATH=""
VOLUMES_ONLY=false
CONFIGS_ONLY=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --volumes-only)
            VOLUMES_ONLY=true
            shift
            ;;
        --configs-only)
            CONFIGS_ONLY=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            BACKUP_PATH="$1"
            shift
            ;;
    esac
done

cd "$PROJECT_DIR"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  OpenTelemetry Stack Restore${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Validate backup path
if [ -z "$BACKUP_PATH" ]; then
    echo -e "${RED}Error: Backup path required${NC}"
    echo ""
    echo "Usage: $0 <backup_path>"
    echo ""
    echo "Available backups:"
    if [ -d "./backups" ]; then
        ls -1 ./backups/ 2>/dev/null | head -10
    else
        echo "  No backups found in ./backups/"
    fi
    exit 1
fi

if [ ! -d "$BACKUP_PATH" ]; then
    echo -e "${RED}Error: Backup directory not found: ${BACKUP_PATH}${NC}"
    exit 1
fi

# Show backup info
echo -e "${BLUE}Backup to restore:${NC} ${BACKUP_PATH}"
if [ -f "${BACKUP_PATH}/manifest.json" ]; then
    echo -e "${BLUE}Backup date:${NC} $(cat "${BACKUP_PATH}/manifest.json" | grep -o '"date":[^,]*' | cut -d'"' -f4)"
fi
echo ""

# List available backups
echo -e "${BLUE}Backup contents:${NC}"
ls -lh "${BACKUP_PATH}/"*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
echo ""

# Confirmation
if [ "$FORCE" != true ]; then
    echo -e "${RED}WARNING: This will overwrite current data!${NC}"
    echo -e "${YELLOW}Services will be stopped during restore.${NC}"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Restore cancelled."
        exit 0
    fi
fi

echo ""

# Stop services
echo -e "${BLUE}Stopping services...${NC}"
docker compose --profile full down 2>/dev/null || docker compose down 2>/dev/null || true
echo -e "  ${GREEN}done${NC}"
echo ""

# Restore volumes
if [ "$CONFIGS_ONLY" != true ]; then
    echo -e "${BLUE}Restoring volumes...${NC}"
    
    for backup_file in "${BACKUP_PATH}"/*.tar.gz; do
        filename=$(basename "$backup_file")
        
        # Skip configs
        if [ "$filename" = "configs.tar.gz" ]; then
            continue
        fi
        
        volume_name="${filename%.tar.gz}"
        
        # Try different volume naming conventions
        full_volume_name=""
        for prefix in "opensource-otel-setup_" "otel_" ""; do
            test_name="${prefix}${volume_name}"
            if docker volume inspect "$test_name" > /dev/null 2>&1; then
                full_volume_name="$test_name"
                break
            fi
        done
        
        echo -n "  Restoring ${volume_name}... "
        
        # Create volume if it doesn't exist
        if [ -z "$full_volume_name" ]; then
            full_volume_name="${volume_name}"
            docker volume create "$full_volume_name" > /dev/null 2>&1 || true
        fi
        
        # Clear and restore
        docker run --rm \
            -v "${full_volume_name}:/dest" \
            -v "${BACKUP_PATH}:/backup:ro" \
            alpine sh -c "rm -rf /dest/* && tar xzf /backup/${filename} -C /dest" 2>/dev/null
        
        echo -e "${GREEN}done${NC}"
    done
    echo ""
fi

# Restore configurations
if [ "$VOLUMES_ONLY" != true ] && [ -f "${BACKUP_PATH}/configs.tar.gz" ]; then
    echo -e "${BLUE}Restoring configurations...${NC}"
    
    # Backup current configs first
    if [ -f "docker-compose.yml" ]; then
        mkdir -p "${PROJECT_DIR}/.config-backup"
        cp docker-compose.yml "${PROJECT_DIR}/.config-backup/" 2>/dev/null || true
        cp otel-collector-config.yaml "${PROJECT_DIR}/.config-backup/" 2>/dev/null || true
    fi
    
    tar xzf "${BACKUP_PATH}/configs.tar.gz" -C "${PROJECT_DIR}/"
    echo -e "  ${GREEN}done${NC}"
    echo ""
fi

# Start services
echo -e "${BLUE}Starting services...${NC}"
docker compose up -d
echo -e "  ${GREEN}done${NC}"
echo ""

# Wait for health
echo -e "${BLUE}Waiting for services to be healthy...${NC}"
sleep 15

# Check status
echo ""
./scripts/status.sh 2>/dev/null || docker compose ps

echo ""
echo -e "${GREEN}✓ Restore complete!${NC}"

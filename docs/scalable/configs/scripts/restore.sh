#!/bin/bash
# =============================================================================
# Restore Script for Observability Stack
# =============================================================================
#
# Restores from a backup created by backup.sh
#
# Usage:
#   ./restore.sh /path/to/backup/20240115_020000
#   ./restore.sh --list                          # List available backups
#   ./restore.sh --volume prometheus-data /path  # Restore single volume

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

BACKUP_DIR="${BACKUP_DIR:-./backups}"

# Help message
show_help() {
  cat << EOF
Usage: $0 [OPTIONS] <backup_path>

Restore observability stack from backup.

Options:
  --list              List available backups
  --volume <name>     Restore only specified volume
  --dry-run           Show what would be restored without doing it
  -h, --help          Show this help message

Examples:
  $0 /backups/20240115_020000           # Full restore
  $0 --volume prometheus-data /backups/20240115_020000
  $0 --list
EOF
}

# List available backups
list_backups() {
  log_info "Available backups in ${BACKUP_DIR}:"
  echo ""
  if [[ -d "$BACKUP_DIR" ]]; then
    for backup in "${BACKUP_DIR}"/*/; do
      if [[ -f "${backup}manifest.txt" ]]; then
        SIZE=$(du -sh "$backup" | cut -f1)
        DATE=$(basename "$backup")
        echo "  ${DATE} (${SIZE})"
      fi
    done
  else
    log_warn "Backup directory not found: ${BACKUP_DIR}"
  fi
}

# Parse arguments
DRY_RUN=false
SINGLE_VOLUME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --list)
      list_backups
      exit 0
      ;;
    --volume)
      SINGLE_VOLUME="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      BACKUP_PATH="$1"
      shift
      ;;
  esac
done

# Validate backup path
if [[ -z "${BACKUP_PATH:-}" ]]; then
  log_error "Backup path required"
  show_help
  exit 1
fi

if [[ ! -d "$BACKUP_PATH" ]]; then
  log_error "Backup path not found: $BACKUP_PATH"
  exit 1
fi

# Show manifest
if [[ -f "${BACKUP_PATH}/manifest.txt" ]]; then
  log_info "Backup manifest:"
  cat "${BACKUP_PATH}/manifest.txt"
  echo ""
fi

# Confirm restore
if [[ "$DRY_RUN" != true ]]; then
  log_warn "This will STOP services and OVERWRITE existing data!"
  read -p "Continue? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    log_info "Restore cancelled"
    exit 0
  fi
fi

# Stop services
if [[ "$DRY_RUN" != true ]]; then
  log_info "Stopping services..."
  docker compose down 2>/dev/null || true
fi

# Determine volumes to restore
if [[ -n "$SINGLE_VOLUME" ]]; then
  VOLUMES=("$SINGLE_VOLUME")
else
  # Note: Volume names match docker-compose-scalable.yaml naming convention
  VOLUMES=(
    "otel-scalable-prometheus"
    "otel-scalable-grafana"
    "otel-scalable-loki"
    "otel-scalable-kafka"
    "otel-scalable-processor"
    "otel-scalable-tempo"
    "otel-scalable-mimir"
  )
fi

# Restore volumes
for volume in "${VOLUMES[@]}"; do
  BACKUP_FILE="${BACKUP_PATH}/${volume}.tar.gz"
  
  if [[ -f "$BACKUP_FILE" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      log_info "[DRY RUN] Would restore ${volume} from ${BACKUP_FILE}"
    else
      log_info "Restoring ${volume}..."
      
      # Create volume if it doesn't exist
      docker volume create "$volume" 2>/dev/null || true
      
      # Restore data
      docker run --rm \
        -v "${volume}:/target" \
        -v "$(realpath "$BACKUP_FILE"):/backup.tar.gz:ro" \
        alpine sh -c "rm -rf /target/* && tar xzf /backup.tar.gz -C /target"
      
      log_info "  ${volume}: restored"
    fi
  else
    log_warn "Backup file not found: ${BACKUP_FILE}"
  fi
done

# Restore configs
if [[ -f "${BACKUP_PATH}/configs.tar.gz" ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY RUN] Would restore configuration files"
  else
    log_info "Restoring configuration files..."
    tar xzf "${BACKUP_PATH}/configs.tar.gz" -C .
    log_info "  Configuration files restored"
  fi
fi

# Summary
log_info "========================================"
if [[ "$DRY_RUN" == true ]]; then
  log_info "Dry run complete - no changes made"
else
  log_info "Restore complete!"
  log_info ""
  log_info "Next steps:"
  log_info "  1. Review configuration files"
  log_info "  2. Start services: docker compose up -d"
  log_info "  3. Verify data: ./scripts/health-check.sh"
fi

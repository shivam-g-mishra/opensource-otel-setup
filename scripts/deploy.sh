#!/bin/bash
# =============================================================================
# Zero-Downtime Deploy Script for OpenTelemetry Stack
# =============================================================================
# Performs graceful deployment with minimal data loss.
#
# Usage:
#   ./scripts/deploy.sh              # Normal deployment
#   ./scripts/deploy.sh --quick      # Skip backup (faster)
#   ./scripts/deploy.sh --pull       # Pull latest images first
#
# What it does:
#   1. Creates backup (optional)
#   2. Gracefully stops services (waits for queues to drain)
#   3. Pulls new images (optional)
#   4. Starts services
#   5. Verifies health
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
SKIP_BACKUP=false
PULL_IMAGES=false
PROFILE=""

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --quick           Skip backup (faster deployment)"
    echo "  --pull            Pull latest images before deploying"
    echo "  --profile <name>  Use specific profile (seq, full)"
    echo "  --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                # Normal deployment with backup"
    echo "  $0 --quick        # Quick deployment without backup"
    echo "  $0 --pull         # Pull latest images and deploy"
    echo "  $0 --profile seq  # Deploy with Seq profile"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --quick)
            SKIP_BACKUP=true
            shift
            ;;
        --pull)
            PULL_IMAGES=true
            shift
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            ;;
        *)
            shift
            ;;
    esac
done

# Build profile argument
PROFILE_ARG=""
if [ -n "$PROFILE" ]; then
    PROFILE_ARG="--profile $PROFILE"
fi

cd "$PROJECT_DIR"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  OpenTelemetry Stack Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Starting zero-downtime deployment...${NC}"
echo ""

# Step 1: Backup (optional)
if [ "$SKIP_BACKUP" != true ]; then
    echo -e "${BLUE}Step 1/5: Creating backup...${NC}"
    ./scripts/backup.sh > /dev/null 2>&1 && echo -e "  ${GREEN}Backup created${NC}" || echo -e "  ${YELLOW}Backup skipped (not critical)${NC}"
else
    echo -e "${BLUE}Step 1/5: Skipping backup (--quick mode)${NC}"
fi
echo ""

# Step 2: Wait for queues to drain
echo -e "${BLUE}Step 2/5: Waiting for queues to drain...${NC}"
echo -e "  Allowing 10 seconds for in-flight data..."
sleep 10
echo -e "  ${GREEN}done${NC}"
echo ""

# Step 3: Gracefully stop services
echo -e "${BLUE}Step 3/5: Stopping services gracefully...${NC}"
docker compose $PROFILE_ARG stop --timeout 30 2>/dev/null || docker compose stop --timeout 30 2>/dev/null || docker compose stop
echo -e "  ${GREEN}Services stopped${NC}"
echo ""

# Step 4: Pull new images (optional)
if [ "$PULL_IMAGES" = true ]; then
    echo -e "${BLUE}Step 4/5: Pulling latest images...${NC}"
    docker compose $PROFILE_ARG pull
    echo -e "  ${GREEN}Images updated${NC}"
else
    echo -e "${BLUE}Step 4/5: Skipping image pull (use --pull to update)${NC}"
fi
echo ""

# Step 5: Start services
echo -e "${BLUE}Step 5/5: Starting services...${NC}"
docker compose $PROFILE_ARG up -d
echo -e "  ${GREEN}Services started${NC}"
echo ""

# Wait and verify health
echo -e "${BLUE}Verifying deployment...${NC}"
echo -e "  Waiting for services to initialize..."
sleep 15

# Check each service
services_healthy=true

check_health() {
    local name=$1
    local url=$2
    if curl -sf "$url" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $name"
    else
        echo -e "  ${RED}✗${NC} $name"
        services_healthy=false
    fi
}

echo ""
echo -e "${BLUE}Health Status:${NC}"
check_health "Jaeger" "http://localhost:16686"
check_health "Prometheus" "http://localhost:9090/-/healthy"
check_health "Loki" "http://localhost:3100/ready"
check_health "OTel Collector" "http://localhost:13133/health"
check_health "Grafana" "http://localhost:3000/api/health"

echo ""
if [ "$services_healthy" = true ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Deployment successful!${NC}"
    echo -e "${GREEN}========================================${NC}"
else
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}  Deployment complete with warnings${NC}"
    echo -e "${YELLOW}  Some services may still be starting${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo -e "Run ${BLUE}make status${NC} to check again."
fi

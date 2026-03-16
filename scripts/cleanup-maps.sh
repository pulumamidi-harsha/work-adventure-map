#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# cleanup-maps.sh — Delete ALL existing maps from a WorkAdventure
# Map Storage environment.
#
# Works for any environment (dev / staging / prod).
# Authenticates with username + password (Basic Auth).
#
# ─────────────────────────────────────────────────────────────
# Usage (interactive — prompts for everything):
#   ./scripts/cleanup-maps.sh
#
# Usage (non-interactive):
#   ENVIRONMENT=staging \
#   MAPSTORAGE_USER=admin \
#   MAPSTORAGE_PASSWORD=mypassword \
#   ./scripts/cleanup-maps.sh
#
# Environment variables (all optional — will prompt if missing):
#   ENVIRONMENT          — dev | staging | prod (or set MAP_STORAGE_URL directly)
#   MAP_STORAGE_URL      — full map-storage URL (overrides ENVIRONMENT)
#   MAPSTORAGE_USER      — username for basic auth
#   MAPSTORAGE_PASSWORD  — password for basic auth
# ─────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}🗑️  WorkAdventure Map Storage — Cleanup${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# ── Helper: get map-storage URL for an environment ────────────
get_map_storage_url() {
  case "$1" in
    dev)     echo "https://virtual-office.dev.dso-os.int.bayer.com/map-storage" ;;
    staging) echo "https://virtual-office.staging.dso-os.int.bayer.com/map-storage" ;;
    prod)    echo "https://virtual-office.dso-os.int.bayer.com/map-storage" ;;
  esac
}

# ═══════════════════════════════════════════════════════════════
# 1. Resolve environment & URL
# ═══════════════════════════════════════════════════════════════
if [ -z "${MAP_STORAGE_URL:-}" ]; then
  if [ -z "${ENVIRONMENT:-}" ]; then
    echo -e "${YELLOW}Select environment:${NC}"
    echo "  1) dev      — virtual-office.dev.dso-os.int.bayer.com"
    echo "  2) staging  — virtual-office.staging.dso-os.int.bayer.com"
    echo "  3) prod     — virtual-office.dso-os.int.bayer.com"
    echo "  4) dev      — workadventure.dev.dso-os.int.bayer.com"
    echo "  5) staging  — workadventure.staging.dso-os.int.bayer.com"
    echo "  6) prod     — workadventure.dso-os.int.bayer.com"
    echo "  7) custom   — enter your own URL"
    echo ""
    read -rp "Choice [1-7]: " ENV_CHOICE

    case "$ENV_CHOICE" in
      1) ENVIRONMENT="dev";     MAP_STORAGE_URL="https://virtual-office.dev.dso-os.int.bayer.com/map-storage" ;;
      2) ENVIRONMENT="staging"; MAP_STORAGE_URL="https://virtual-office.staging.dso-os.int.bayer.com/map-storage" ;;
      3) ENVIRONMENT="prod";    MAP_STORAGE_URL="https://virtual-office.dso-os.int.bayer.com/map-storage" ;;
      4) ENVIRONMENT="dev";     MAP_STORAGE_URL="https://workadventure.dev.dso-os.int.bayer.com/map-storage" ;;
      5) ENVIRONMENT="staging"; MAP_STORAGE_URL="https://workadventure.staging.dso-os.int.bayer.com/map-storage" ;;
      6) ENVIRONMENT="prod";    MAP_STORAGE_URL="https://workadventure.dso-os.int.bayer.com/map-storage" ;;
      7)
        read -rp "Enter Map Storage URL (e.g. https://host/map-storage): " MAP_STORAGE_URL
        ENVIRONMENT="custom"
        ;;
      *) echo -e "${RED}❌ Invalid choice${NC}"; exit 1 ;;
    esac
  fi

  if [ -z "${MAP_STORAGE_URL:-}" ]; then
    MAP_STORAGE_URL="$(get_map_storage_url "$ENVIRONMENT")"
  fi
fi

echo -e "📍 Environment    : ${BOLD}${ENVIRONMENT:-custom}${NC}"
echo -e "📍 Map Storage URL: ${CYAN}${MAP_STORAGE_URL}${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════
# 2. Resolve username & password
# ═══════════════════════════════════════════════════════════════
if [ -z "${MAPSTORAGE_USER:-}" ]; then
  read -rp "👤 Enter username: " MAPSTORAGE_USER
fi

if [ -z "${MAPSTORAGE_USER}" ]; then
  echo -e "${RED}❌ Username is required${NC}"
  exit 1
fi

if [ -z "${MAPSTORAGE_PASSWORD:-}" ]; then
  read -rsp "🔑 Enter password: " MAPSTORAGE_PASSWORD
  echo ""
fi

if [ -z "${MAPSTORAGE_PASSWORD}" ]; then
  echo -e "${RED}❌ Password is required${NC}"
  exit 1
fi

AUTH="${MAPSTORAGE_USER}:${MAPSTORAGE_PASSWORD}"
echo -e "👤 User: ${CYAN}${MAPSTORAGE_USER}${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════
# 3. Fetch existing maps
# ═══════════════════════════════════════════════════════════════
echo "📋 Fetching existing maps..."

# The map-storage API:  GET /map-storage/maps  → {"maps":{"name.wam":{...}, ...}}
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -u "${AUTH}" \
  "${MAP_STORAGE_URL}/maps" 2>/dev/null || echo -e "\n000")

HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed '$d')
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)

if [ "$HTTP_CODE" != "200" ]; then
  echo -e "${RED}❌ Failed to fetch maps (HTTP ${HTTP_CODE})${NC}"
  echo "   Response: $HTTP_BODY"
  echo ""
  echo -e "${YELLOW}💡 Tip: If the URL is on a private subnet, you may need to port-forward first:${NC}"
  echo "   kubectl port-forward svc/virtual-office-map-storage 8080:80 -n default"
  echo "   Then re-run with: MAP_STORAGE_URL=http://localhost:8080/map-storage ./scripts/cleanup-maps.sh"
  exit 1
fi

# Parse map keys — try different JSON structures
MAP_KEYS=$(echo "$HTTP_BODY" | jq -r '.maps // {} | keys[]' 2>/dev/null || \
           echo "$HTTP_BODY" | jq -r '.[] | .mapUrl // .name // empty' 2>/dev/null || \
           echo "$HTTP_BODY" | jq -r 'keys[]' 2>/dev/null || true)

if [ -z "$MAP_KEYS" ]; then
  echo -e "${GREEN}✅ No existing maps found — nothing to delete${NC}"
  exit 0
fi

MAP_COUNT=$(echo "$MAP_KEYS" | wc -l | tr -d ' ')
echo -e "   Found ${YELLOW}${MAP_COUNT}${NC} maps:"
echo ""
echo "$MAP_KEYS" | while read -r KEY; do
  echo -e "      • ${KEY}"
done
echo ""

# ═══════════════════════════════════════════════════════════════
# 4. Confirm deletion (interactive only)
# ═══════════════════════════════════════════════════════════════
if [ -t 0 ] && [ -z "${CI:-}" ]; then
  echo -e "${RED}⚠️  This will delete ALL ${MAP_COUNT} maps from ${ENVIRONMENT:-custom}!${NC}"
  read -rp "Are you sure? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
  fi
  echo ""
fi

# ═══════════════════════════════════════════════════════════════
# 5. Delete each map
# ═══════════════════════════════════════════════════════════════
DELETE_OK=0
DELETE_FAIL=0

echo "🗑️  Deleting maps..."
while read -r MAP_KEY; do
  echo -n "   🗑️  ${MAP_KEY} ... "

  # URL-encode the map key (spaces, parentheses, etc.)
  ENCODED_KEY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${MAP_KEY}'))" 2>/dev/null || echo "$MAP_KEY")

  # DELETE /map-storage/<name>.wam  → 204 No Content
  DEL_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${AUTH}" \
    -X DELETE \
    "${MAP_STORAGE_URL}/${ENCODED_KEY}" 2>/dev/null || echo "000")

  if [ "$DEL_CODE" = "200" ] || [ "$DEL_CODE" = "204" ] || [ "$DEL_CODE" = "201" ]; then
    echo -e "${GREEN}✅${NC}"
    DELETE_OK=$((DELETE_OK + 1))
  else
    echo -e "${RED}❌ (HTTP ${DEL_CODE})${NC}"
    DELETE_FAIL=$((DELETE_FAIL + 1))
  fi
done <<< "$MAP_KEYS"

echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}✨ Cleanup Complete!${NC}"
echo -e "${CYAN}=========================================${NC}"
echo -e "  🎯 Environment : ${BOLD}${ENVIRONMENT:-custom}${NC}"
echo -e "  ✅ Deleted      : ${DELETE_OK}"
echo -e "  ❌ Failed       : ${DELETE_FAIL}"
echo -e "  📊 Total        : ${MAP_COUNT}"
echo ""

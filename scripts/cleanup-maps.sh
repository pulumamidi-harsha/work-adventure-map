#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# cleanup-maps.sh — Delete ALL existing maps from a WorkAdventure
# Map Storage environment.
#
# Works for any environment (dev / staging / prod).
#
# Usage (interactive — prompts for everything):
#   ./scripts/cleanup-maps.sh
#
# Usage (non-interactive — CI/CD):
#   MAP_STORAGE_URL="https://..." \
#   MAP_STORAGE_API_KEY="your-api-key" \
#   ./scripts/cleanup-maps.sh
#
# Required env vars (or will prompt):
#   MAP_STORAGE_URL     — e.g. https://virtual-office.staging.dso-os.int.bayer.com/map-storage/api
#   MAP_STORAGE_API_KEY — API key for authentication
# ─────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}🗑️  WorkAdventure Map Storage — Cleanup${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# ── Resolve MAP_STORAGE_URL ──────────────────────────────────
if [ -z "${MAP_STORAGE_URL:-}" ]; then
  echo -e "${YELLOW}Select environment:${NC}"
  echo "  1) dev      — virtual-office.dev.dso-os.int.bayer.com"
  echo "  2) staging  — virtual-office.staging.dso-os.int.bayer.com"
  echo "  3) prod     — virtual-office.dso-os.int.bayer.com"
  echo "  4) custom   — enter your own URL"
  echo ""
  read -rp "Choice [1-4]: " ENV_CHOICE

  case "$ENV_CHOICE" in
    1) MAP_STORAGE_URL="https://virtual-office.dev.dso-os.int.bayer.com/map-storage/api" ;;
    2) MAP_STORAGE_URL="https://virtual-office.staging.dso-os.int.bayer.com/map-storage/api" ;;
    3) MAP_STORAGE_URL="https://virtual-office.dso-os.int.bayer.com/map-storage/api" ;;
    4) read -rp "Enter Map Storage URL: " MAP_STORAGE_URL ;;
    *) echo -e "${RED}❌ Invalid choice${NC}"; exit 1 ;;
  esac
fi

echo -e "📍 Map Storage URL: ${CYAN}${MAP_STORAGE_URL}${NC}"
echo ""

# ── Resolve API Key ──────────────────────────────────────────
if [ -z "${MAP_STORAGE_API_KEY:-}" ]; then
  read -rsp "🔑 Enter MAP_STORAGE_API_KEY: " MAP_STORAGE_API_KEY
  echo ""
fi

if [ -z "${MAP_STORAGE_API_KEY}" ]; then
  echo -e "${RED}❌ MAP_STORAGE_API_KEY is required${NC}"
  exit 1
fi

# ── Fetch existing maps ──────────────────────────────────────
echo "📋 Fetching existing maps..."
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: Bearer ${MAP_STORAGE_API_KEY}" \
  "${MAP_STORAGE_URL}/maps" 2>/dev/null || echo -e "\n000")

HTTP_BODY=$(echo "$HTTP_RESPONSE" | head -n -1)
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)

if [ "$HTTP_CODE" != "200" ]; then
  echo -e "${RED}❌ Failed to fetch maps (HTTP ${HTTP_CODE})${NC}"
  echo "   Response: $HTTP_BODY"
  exit 1
fi

MAP_KEYS=$(echo "$HTTP_BODY" | jq -r '.maps // {} | keys[]' 2>/dev/null || true)

if [ -z "$MAP_KEYS" ]; then
  echo -e "${GREEN}✅ No existing maps found — nothing to delete${NC}"
  exit 0
fi

MAP_COUNT=$(echo "$MAP_KEYS" | wc -l | tr -d ' ')
echo -e "   Found ${YELLOW}${MAP_COUNT}${NC} maps"
echo ""

# ── Confirm in interactive mode ──────────────────────────────
if [ -t 0 ] && [ -z "${CI:-}" ]; then
  echo -e "${RED}⚠️  This will delete ALL ${MAP_COUNT} maps!${NC}"
  read -rp "Are you sure? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
  fi
  echo ""
fi

# ── Delete each map ──────────────────────────────────────────
DELETE_OK=0
DELETE_FAIL=0

echo "🗑️  Deleting maps..."
echo "$MAP_KEYS" | while read -r MAP_KEY; do
  echo -n "   🗑️  $MAP_KEY ... "
  DEL_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${MAP_STORAGE_API_KEY}" \
    -X DELETE \
    "${MAP_STORAGE_URL}/${MAP_KEY}" 2>/dev/null || echo "000")

  if [ "$DEL_CODE" = "200" ] || [ "$DEL_CODE" = "204" ] || [ "$DEL_CODE" = "201" ]; then
    echo -e "${GREEN}✅${NC}"
    DELETE_OK=$((DELETE_OK + 1))
  else
    echo -e "${RED}❌ (HTTP ${DEL_CODE})${NC}"
    DELETE_FAIL=$((DELETE_FAIL + 1))
  fi
done

echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}✨ Cleanup Complete!${NC}"
echo -e "${CYAN}=========================================${NC}"
echo -e "   ✅ Deleted: ${DELETE_OK:-$MAP_COUNT}"
echo -e "   ❌ Failed : ${DELETE_FAIL:-0}"
echo ""

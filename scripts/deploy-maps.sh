#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# deploy-maps.sh — Build, cleanup & upload WorkAdventure maps
#                   for any environment (dev / staging / prod).
#
# What it does:
#   1. Replaces embedded domains in .tmj files for the target env
#   2. Runs npm run build  (TypeScript + Vite tileset optimisation)
#   3. Creates a dist/ zip artifact
#   4. Deletes all existing maps from map-storage
#   5. Uploads the zip to map-storage
#
# Uses username/password (Basic Auth) — same as the Map Storage UI.
#
# ─────────────────────────────────────────────────────────────
# Usage:
#
#   Interactive (prompts for everything):
#     ./scripts/deploy-maps.sh
#
#   Build only (no upload):
#     ENVIRONMENT=staging SKIP_UPLOAD=true ./scripts/deploy-maps.sh
#
#   Full deploy (non-interactive):
#     ENVIRONMENT=staging \
#     MAPSTORAGE_USER=admin \
#     MAPSTORAGE_PASSWORD=mypassword \
#     ./scripts/deploy-maps.sh
#
# Environment variables (all optional — will prompt if missing):
#   ENVIRONMENT          — dev | staging | prod
#   MAPSTORAGE_USER      — username for map-storage basic auth
#   MAPSTORAGE_PASSWORD  — password for map-storage basic auth
#   MAP_STORAGE_URL      — override the auto-detected map-storage URL
#   SKIP_UPLOAD          — true = build only, no upload (default: false)
#   SKIP_CLEANUP         — true = don't delete existing maps (default: false)
#   SKIP_BUILD           — true = skip build, use existing dist/ (default: false)
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Resolve project root (one level up from scripts/) ─────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}🗺️  WorkAdventure Map Deploy${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# ── Domain mapping functions (bash 3.x compatible) ────────────
SOURCE_DOMAIN="staging.dso-os.int.bayer.com"
SOURCE_DIRECTORY_DOMAIN="d3fmrqmvjnwn6m.cloudfront.net"

get_app_domain() {
  case "$1" in
    dev)     echo "dev.dso-os.int.bayer.com" ;;
    staging) echo "staging.dso-os.int.bayer.com" ;;
    prod)    echo "dso-os.int.bayer.com" ;;
  esac
}

get_vo_domain() {
  case "$1" in
    dev)     echo "virtual-office.dev.dso-os.int.bayer.com" ;;
    staging) echo "virtual-office.staging.dso-os.int.bayer.com" ;;
    prod)    echo "virtual-office.dso-os.int.bayer.com" ;;
  esac
}

get_directory_domain() {
  case "$1" in
    dev)     echo "doizkviqkzeyt.cloudfront.net" ;;
    staging) echo "d3fmrqmvjnwn6m.cloudfront.net" ;;
    prod)    echo "d1ygxnweks0xtq.cloudfront.net" ;;
    *)       echo "d3fmrqmvjnwn6m.cloudfront.net" ;;
  esac
}

# ═══════════════════════════════════════════════════════════════
# STEP 0 — Gather parameters
# ═══════════════════════════════════════════════════════════════

# ── Environment ───────────────────────────────────────────────
if [ -z "${ENVIRONMENT:-}" ]; then
  echo -e "${YELLOW}Select target environment:${NC}"
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

ENVIRONMENT="$(echo "$ENVIRONMENT" | tr '[:upper:]' '[:lower:]')"

case "$ENVIRONMENT" in
  dev|staging|prod|custom) ;;
  *) echo -e "${RED}❌ Invalid environment: $ENVIRONMENT (must be dev|staging|prod)${NC}"; exit 1 ;;
esac

TARGET_APP_DOMAIN="$(get_app_domain "$ENVIRONMENT")"
TARGET_VO_DOMAIN="$(get_vo_domain "$ENVIRONMENT")"
MAP_STORAGE_URL="${MAP_STORAGE_URL:-https://${TARGET_VO_DOMAIN}/map-storage}"

echo -e "🎯 Environment     : ${BOLD}${ENVIRONMENT}${NC}"
echo -e "🌐 App domain      : ${CYAN}${TARGET_APP_DOMAIN}${NC}"
echo -e "📡 Map-storage     : ${CYAN}${MAP_STORAGE_URL}${NC}"
echo ""

# ── Auth (username + password) ────────────────────────────────
SKIP_UPLOAD="${SKIP_UPLOAD:-false}"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"
SKIP_BUILD="${SKIP_BUILD:-false}"

if [ "$SKIP_UPLOAD" != "true" ]; then
  if [ -z "${MAPSTORAGE_USER:-}" ]; then
    read -rp "👤 Enter username: " MAPSTORAGE_USER
  fi
  if [ -z "${MAPSTORAGE_USER}" ]; then
    echo -e "${RED}❌ Username is required${NC}"; exit 1
  fi

  if [ -z "${MAPSTORAGE_PASSWORD:-}" ]; then
    read -rsp "🔑 Enter password: " MAPSTORAGE_PASSWORD
    echo ""
  fi
  if [ -z "${MAPSTORAGE_PASSWORD}" ]; then
    echo -e "${YELLOW}⚠️  No password provided — will build only (no upload)${NC}"
    SKIP_UPLOAD="true"
  fi

  if [ "$SKIP_UPLOAD" != "true" ]; then
    AUTH="${MAPSTORAGE_USER}:${MAPSTORAGE_PASSWORD}"
    echo -e "👤 User: ${CYAN}${MAPSTORAGE_USER}${NC}"
    echo ""
  fi
fi

# ═══════════════════════════════════════════════════════════════
# STEP 1 — Replace domains in .tmj files (automatic for all envs)
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}━━━ Step 1: Replace domains in .tmj files ━━━${NC}"

TMJ_COUNT=$(ls *.tmj 2>/dev/null | wc -l | tr -d ' ')
echo "   📄 Found ${TMJ_COUNT} .tmj files"

# Both Virtual Office and CloudFront Directory domains are replaced automatically.
TARGET_DIRECTORY_DOMAIN="$(get_directory_domain "$ENVIRONMENT")"

declare -a REPLACE_FROM=("${SOURCE_DOMAIN}" "${SOURCE_DIRECTORY_DOMAIN}")
declare -a REPLACE_TO=("${TARGET_APP_DOMAIN}" "${TARGET_DIRECTORY_DOMAIN}")
declare -a REPLACE_LABEL=("Virtual Office domain" "CloudFront Directory domain")

TOTAL_REPLACED=0
for i in 0 1; do
  FROM="${REPLACE_FROM[$i]}"
  TO="${REPLACE_TO[$i]}"
  LABEL="${REPLACE_LABEL[$i]}"

  if [ "$FROM" = "$TO" ]; then
    echo -e "   ✅ ${LABEL}: source = target (${FROM}) — no replacement needed"
    continue
  fi

  BEFORE=$(grep -c "${FROM}" *.tmj 2>/dev/null | awk -F: '{sum+=$2} END{print sum+0}' || echo 0)
  echo -e "   🔄 ${LABEL}: '${FROM}' → '${TO}' (${BEFORE} occurrences)"

  if [ "$BEFORE" -gt 0 ]; then
    if [ "$(uname)" = "Darwin" ]; then
      sed -i '' "s|${FROM}|${TO}|g" *.tmj
    else
      sed -i "s|${FROM}|${TO}|g" *.tmj
    fi
    TOTAL_REPLACED=$((TOTAL_REPLACED + BEFORE))
  fi
done

echo -e "   📊 Total replacements: ${GREEN}${TOTAL_REPLACED}${NC}"

# ═══════════════════════════════════════════════════════════════
# STEP 2 — Install dependencies & Build
# ═══════════════════════════════════════════════════════════════
if [ "$SKIP_BUILD" != "true" ]; then
  echo ""
  echo -e "${BOLD}━━━ Step 2: Install dependencies ━━━${NC}"
  npm ci 2>&1 | tail -5

  echo ""
  echo -e "${BOLD}━━━ Step 3: Build maps ━━━${NC}"
  echo "   🏗️  Running npm run build ..."
  npm run build 2>&1 | tail -15
else
  echo ""
  echo -e "${BOLD}━━━ Steps 2-3: Skipped (SKIP_BUILD=true) ━━━${NC}"
fi

DIST_TMJ=$(find dist -name "*.tmj" 2>/dev/null | wc -l | tr -d ' ')
DIST_SIZE=$(du -sh dist/ 2>/dev/null | cut -f1)
echo ""
echo -e "   📊 Built ${GREEN}${DIST_TMJ}${NC} .tmj files"
echo -e "   📦 dist/ size: ${DIST_SIZE}"

# ═══════════════════════════════════════════════════════════════
# STEP 3 — Create zip artifact
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}━━━ Step 4: Create zip artifact ━━━${NC}"

ARTIFACT_NAME="maps-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).zip"
ARTIFACT_DIR="${PROJECT_ROOT}/artifacts"
mkdir -p "$ARTIFACT_DIR"
ARTIFACT_PATH="${ARTIFACT_DIR}/${ARTIFACT_NAME}"

(cd dist && zip -r "$ARTIFACT_PATH" . -x '*.map') 2>&1 | tail -5
ARTIFACT_SIZE=$(du -h "$ARTIFACT_PATH" | cut -f1)
echo -e "   📦 ${GREEN}${ARTIFACT_PATH}${NC} (${ARTIFACT_SIZE})"

# ═══════════════════════════════════════════════════════════════
# STEP 4 — Revert domain changes (keep source .tmj files clean)
# ═══════════════════════════════════════════════════════════════
if [ "$ENVIRONMENT" != "staging" ]; then
  echo ""
  echo -e "${BOLD}━━━ Step 5: Revert domain changes in source files ━━━${NC}"
  git checkout -- *.tmj 2>/dev/null || true
  echo -e "   ✅ Source .tmj files restored to canonical (${SOURCE_DOMAIN})"
fi

# ═══════════════════════════════════════════════════════════════
# STEP 5 — Upload or show instructions
# ═══════════════════════════════════════════════════════════════
if [ "$SKIP_UPLOAD" = "true" ]; then
  echo ""
  echo -e "${YELLOW}=========================================${NC}"
  echo -e "${YELLOW}📦 Build complete — upload skipped${NC}"
  echo -e "${YELLOW}=========================================${NC}"
  echo ""
  echo -e "Artifact ready at:"
  echo -e "  ${CYAN}${ARTIFACT_PATH}${NC}"
  echo ""
  echo -e "To upload via Map Storage UI:"
  echo -e "  Open ${CYAN}https://${TARGET_VO_DOMAIN}/map-storage/ui${NC}"
  echo -e "  Upload the zip file"
  echo ""
  echo -e "Or re-run this script to deploy:"
  echo -e "  ENVIRONMENT=${ENVIRONMENT} ./scripts/deploy-maps.sh"
  exit 0
fi

# ── Cleanup existing maps ────────────────────────────────────
echo ""
echo -e "${BOLD}━━━ Step 6: Cleanup existing maps ━━━${NC}"

if [ "$SKIP_CLEANUP" != "true" ]; then
  echo "📋 Fetching existing maps..."
  MAPS_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -u "${AUTH}" \
    "${MAP_STORAGE_URL}/maps" 2>/dev/null || echo -e "\n000")

  MAPS_BODY=$(echo "$MAPS_RESPONSE" | sed '$d')
  MAPS_CODE=$(echo "$MAPS_RESPONSE" | tail -n 1)

  if [ "$MAPS_CODE" = "200" ]; then
    MAP_KEYS=$(echo "$MAPS_BODY" | jq -r '.maps // {} | keys[]' 2>/dev/null || true)

    if [ -z "$MAP_KEYS" ]; then
      echo -e "   ${GREEN}✅ No existing maps — nothing to delete${NC}"
    else
      MAP_COUNT=$(echo "$MAP_KEYS" | wc -l | tr -d ' ')
      echo -e "   Found ${YELLOW}${MAP_COUNT}${NC} existing maps — deleting..."

      DEL_OK=0
      DEL_FAIL=0
      while read -r MAP_KEY; do
        ENCODED_KEY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${MAP_KEY}'))" 2>/dev/null || echo "$MAP_KEY")
        DEL_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
          -u "${AUTH}" \
          -X DELETE \
          "${MAP_STORAGE_URL}/${ENCODED_KEY}" 2>/dev/null || echo "000")

        if [ "$DEL_CODE" = "200" ] || [ "$DEL_CODE" = "204" ]; then
          DEL_OK=$((DEL_OK + 1))
        else
          echo -e "   ${RED}❌ Failed to delete ${MAP_KEY} (HTTP ${DEL_CODE})${NC}"
          DEL_FAIL=$((DEL_FAIL + 1))
        fi
      done <<< "$MAP_KEYS"

      echo -e "   ✅ Deleted: ${DEL_OK}  ❌ Failed: ${DEL_FAIL}"
    fi
  else
    echo -e "   ${RED}❌ Failed to fetch maps (HTTP ${MAPS_CODE})${NC}"
    echo -e "   ${YELLOW}Continuing with upload anyway...${NC}"
  fi
else
  echo -e "   ⏭️  Skipped (SKIP_CLEANUP=true)"
fi

# ── Upload zip to map-storage ─────────────────────────────────
echo ""
echo -e "${BOLD}━━━ Step 7: Upload to map-storage ━━━${NC}"
echo -e "   📤 Uploading ${ARTIFACT_NAME} to ${CYAN}${MAP_STORAGE_URL}/upload${NC}"
echo ""

UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -u "${AUTH}" \
  -X POST \
  -F "file=@${ARTIFACT_PATH}" \
  "${MAP_STORAGE_URL}/upload" 2>/dev/null || echo -e "\n000")

UPLOAD_BODY=$(echo "$UPLOAD_RESPONSE" | sed '$d')
UPLOAD_CODE=$(echo "$UPLOAD_RESPONSE" | tail -n 1)

if [ "$UPLOAD_CODE" = "200" ] || [ "$UPLOAD_CODE" = "201" ]; then
  echo -e "   ${GREEN}✅ Upload successful!${NC}"
  echo -e "   📝 Response: ${UPLOAD_BODY}"
else
  echo -e "   ${RED}❌ Upload failed (HTTP ${UPLOAD_CODE})${NC}"
  echo -e "   📝 Response: ${UPLOAD_BODY}"
  echo ""
  echo -e "   ${YELLOW}💡 You can manually upload via:${NC}"
  echo -e "      Open ${CYAN}https://${TARGET_VO_DOMAIN}/map-storage/ui${NC}"
  echo -e "      Upload: ${ARTIFACT_PATH}"
  exit 1
fi

# ── Verify maps ───────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━ Step 8: Verify uploaded maps ━━━${NC}"

sleep 2  # brief wait for map-storage to process

VERIFY_RESPONSE=$(curl -s -u "${AUTH}" "${MAP_STORAGE_URL}/maps" 2>/dev/null || echo '{}')
VERIFY_COUNT=$(echo "$VERIFY_RESPONSE" | jq '.maps | length' 2>/dev/null || echo "?")

echo -e "   📊 Maps now in ${ENVIRONMENT}: ${GREEN}${VERIFY_COUNT}${NC}"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✅ Deploy Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "  🎯 Environment : ${BOLD}${ENVIRONMENT}${NC}"
echo -e "  🌐 App domain  : ${TARGET_APP_DOMAIN}"
echo -e "  📦 Artifact    : ${ARTIFACT_PATH}"
echo -e "  📊 Maps uploaded: ${VERIFY_COUNT}"
echo -e "  🔗 Map Storage : https://${TARGET_VO_DOMAIN}/map-storage/ui/maps"
echo ""

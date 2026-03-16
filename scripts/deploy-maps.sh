#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# deploy-maps.sh — Build & upload WorkAdventure maps for any
#                   environment (dev / staging / prod).
#
# What it does:
#   1. Replaces embedded domains in .tmj files for the target env
#   2. Runs npm run build  (TypeScript + Vite tileset optimisation)
#   3. Creates a dist/ zip artifact
#   4. (Optional) Deletes all existing maps on the target env
#   5. (Optional) Uploads the build to map-storage via API
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
#   Full deploy (with network access):
#     ENVIRONMENT=staging \
#     MAP_STORAGE_URL=https://virtual-office.staging.dso-os.int.bayer.com/map-storage/api \
#     MAP_STORAGE_API_KEY=<key> \
#     UPLOAD_DIRECTORY=/ \
#     ./scripts/deploy-maps.sh
#
# Environment variables (all optional — will prompt if missing):
#   ENVIRONMENT          — dev | staging | prod
#   MAP_STORAGE_URL      — map-storage API endpoint
#   MAP_STORAGE_API_KEY  — API key for authentication
#   UPLOAD_DIRECTORY     — upload path on server (default: /)
#   SKIP_UPLOAD          — true = build only, no upload (default: false)
#   SKIP_CLEANUP         — true = don't delete existing maps (default: false)
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
# Source domain used in the repository .tmj files (canonical):
SOURCE_DOMAIN="staging.dso-os.int.bayer.com"

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

# ═══════════════════════════════════════════════════════════════
# STEP 0 — Gather parameters
# ═══════════════════════════════════════════════════════════════

# ── Environment ───────────────────────────────────────────────
if [ -z "${ENVIRONMENT:-}" ]; then
  echo -e "${YELLOW}Select target environment:${NC}"
  echo "  1) dev"
  echo "  2) staging"
  echo "  3) prod"
  echo ""
  read -rp "Choice [1-3]: " ENV_CHOICE
  case "$ENV_CHOICE" in
    1) ENVIRONMENT="dev" ;;
    2) ENVIRONMENT="staging" ;;
    3) ENVIRONMENT="prod" ;;
    *) echo -e "${RED}❌ Invalid choice${NC}"; exit 1 ;;
  esac
fi

# Lowercase
ENVIRONMENT="$(echo "$ENVIRONMENT" | tr '[:upper:]' '[:lower:]')"

case "$ENVIRONMENT" in
  dev|staging|prod) ;;
  *) echo -e "${RED}❌ Invalid environment: $ENVIRONMENT (must be dev|staging|prod)${NC}"; exit 1 ;;
esac

TARGET_APP_DOMAIN="$(get_app_domain "$ENVIRONMENT")"
TARGET_VO_DOMAIN="$(get_vo_domain "$ENVIRONMENT")"
DEFAULT_MAP_STORAGE_URL="https://${TARGET_VO_DOMAIN}/map-storage/api"

echo -e "🎯 Environment     : ${BOLD}${ENVIRONMENT}${NC}"
echo -e "🌐 App domain      : ${CYAN}${TARGET_APP_DOMAIN}${NC}"
echo -e "📡 Map-storage     : ${CYAN}${TARGET_VO_DOMAIN}${NC}"
echo ""

# ── Upload settings ───────────────────────────────────────────
SKIP_UPLOAD="${SKIP_UPLOAD:-false}"
SKIP_CLEANUP="${SKIP_CLEANUP:-false}"

if [ "$SKIP_UPLOAD" != "true" ]; then
  # Map Storage URL
  if [ -z "${MAP_STORAGE_URL:-}" ]; then
    echo -e "${YELLOW}Map Storage URL${NC} (press Enter for default):"
    echo -e "  Default: ${CYAN}${DEFAULT_MAP_STORAGE_URL}${NC}"
    read -rp "  URL: " MAP_STORAGE_URL
    MAP_STORAGE_URL="${MAP_STORAGE_URL:-$DEFAULT_MAP_STORAGE_URL}"
  fi

  # API Key
  if [ -z "${MAP_STORAGE_API_KEY:-}" ]; then
    read -rsp "🔑 Enter MAP_STORAGE_API_KEY: " MAP_STORAGE_API_KEY
    echo ""
  fi

  if [ -z "${MAP_STORAGE_API_KEY}" ]; then
    echo -e "${YELLOW}⚠️  No API key provided — will build only (no upload)${NC}"
    SKIP_UPLOAD="true"
  fi

  UPLOAD_DIRECTORY="${UPLOAD_DIRECTORY:-/}"
fi

# ═══════════════════════════════════════════════════════════════
# STEP 1 — Replace domains in .tmj files
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}━━━ Step 1: Replace domains in .tmj files ━━━${NC}"

TMJ_COUNT=$(ls *.tmj 2>/dev/null | wc -l | tr -d ' ')
echo "   📄 Found ${TMJ_COUNT} .tmj files"

if [ "$ENVIRONMENT" = "staging" ]; then
  echo -e "   ✅ Source domain = target domain (${SOURCE_DOMAIN}) — no replacement needed"
else
  BEFORE=$(grep -c "${SOURCE_DOMAIN}" *.tmj 2>/dev/null | awk -F: '{sum+=$2} END{print sum+0}' || echo 0)
  echo -e "   🔄 Replacing '${SOURCE_DOMAIN}' → '${TARGET_APP_DOMAIN}'"
  echo -e "      Occurrences: ${BEFORE}"

  if [ "$BEFORE" -gt 0 ]; then
    # macOS sed uses -i '' , Linux uses -i
    if [ "$(uname)" = "Darwin" ]; then
      sed -i '' "s|${SOURCE_DOMAIN}|${TARGET_APP_DOMAIN}|g" *.tmj
    else
      sed -i "s|${SOURCE_DOMAIN}|${TARGET_APP_DOMAIN}|g" *.tmj
    fi
  fi

  AFTER=$(grep -c "${SOURCE_DOMAIN}" *.tmj 2>/dev/null | awk -F: '{sum+=$2} END{print sum+0}' || echo 0)
  echo -e "      Remaining: ${AFTER}"
fi

# ═══════════════════════════════════════════════════════════════
# STEP 2 — Install dependencies & Build
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}━━━ Step 2: Install dependencies ━━━${NC}"
npm ci 2>&1 | tail -5

echo ""
echo -e "${BOLD}━━━ Step 3: Build maps ━━━${NC}"
echo "   🏗️  Running npm run build ..."
npm run build 2>&1 | tail -15

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

(cd dist && zip -r "$ARTIFACT_DIR/$ARTIFACT_NAME" . -x '*.map') 2>&1 | tail -5
ARTIFACT_SIZE=$(du -h "$ARTIFACT_DIR/$ARTIFACT_NAME" | cut -f1)
echo -e "   📦 ${GREEN}${ARTIFACT_DIR}/${ARTIFACT_NAME}${NC} (${ARTIFACT_SIZE})"
echo -e "   💡 You can upload this zip manually via the Map Storage UI"

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
  echo -e "  ${CYAN}${ARTIFACT_DIR}/${ARTIFACT_NAME}${NC}"
  echo ""
  echo -e "To upload via Map Storage UI:"
  echo -e "  Open ${CYAN}https://${TARGET_VO_DOMAIN}/map-storage/ui${NC}"
  echo -e "  Upload the zip file"
  echo ""
  echo -e "Or re-run this script with API access:"
  echo -e "  ENVIRONMENT=${ENVIRONMENT} \\"
  echo -e "  MAP_STORAGE_URL=${DEFAULT_MAP_STORAGE_URL} \\"
  echo -e "  MAP_STORAGE_API_KEY=<key> \\"
  echo -e "  ./scripts/deploy-maps.sh"
  exit 0
fi

# ── Cleanup existing maps ────────────────────────────────────
echo ""
echo -e "${BOLD}━━━ Step 6: Cleanup existing maps ━━━${NC}"

if [ "$SKIP_CLEANUP" != "true" ]; then
  export MAP_STORAGE_URL
  export MAP_STORAGE_API_KEY
  export CI=true
  chmod +x "$SCRIPT_DIR/cleanup-maps.sh"
  "$SCRIPT_DIR/cleanup-maps.sh"
else
  echo -e "   ⏭️  Skipped (SKIP_CLEANUP=true)"
fi

# ── Upload to map-storage ────────────────────────────────────
echo ""
echo -e "${BOLD}━━━ Step 7: Upload to map-storage ━━━${NC}"
echo -e "   📤 Uploading to ${CYAN}${MAP_STORAGE_URL}${NC}"
echo -e "   📁 Directory: ${UPLOAD_DIRECTORY}"

export MAP_STORAGE_URL
export MAP_STORAGE_API_KEY
export UPLOAD_DIRECTORY
npm run upload-only

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✅ Deploy Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "  🎯 Environment : ${BOLD}${ENVIRONMENT}${NC}"
echo -e "  🌐 Domain      : ${TARGET_APP_DOMAIN}"
echo -e "  📦 Artifact    : ${ARTIFACT_DIR}/${ARTIFACT_NAME}"
echo -e "  🔗 Map Storage : https://${TARGET_VO_DOMAIN}/map-storage/ui/maps"
echo ""

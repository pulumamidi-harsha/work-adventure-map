#!/bin/bash
# One-time full sync of all maps to WorkAdventure MapStorage
# This script syncs ALL maps from GitHub Pages to both Dev and Staging

set -e

GITHUB_PAGES_BASE_URL="https://pulumamidi-harsha.github.io/work-adventure-map/maps"
MAPSTORAGE_USER="${MAPSTORAGE_USER:-admin}"
MAPSTORAGE_PASSWORD="${MAPSTORAGE_PASSWORD:-admin123}"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "========================================="
echo "🚀 WorkAdventure Full Map Sync"
echo "========================================="
echo ""

# Function to sync maps to an environment
sync_to_environment() {
    local ENV_NAME=$1
    local MAPSTORAGE_API_URL=$2
    local MAPSTORAGE_AUTH="$MAPSTORAGE_USER:$MAPSTORAGE_PASSWORD"
    
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}Syncing to $ENV_NAME${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo "MapStorage URL: $MAPSTORAGE_API_URL"
    echo ""
    
    # Test connection
    echo "🔌 Testing MapStorage connection..."
    if ! curl -s -f -u "$MAPSTORAGE_AUTH" "$MAPSTORAGE_API_URL/maps" > /dev/null 2>&1; then
        echo -e "${RED}❌ ERROR: Cannot connect to MapStorage${NC}"
        echo "Please check URL and credentials"
        return 1
    fi
    echo -e "${GREEN}✅ Connection OK${NC}"
    echo ""
    
    # Get existing maps
    echo "📋 Fetching existing maps..."
    EXISTING_MAPS=$(curl -s -u "$MAPSTORAGE_AUTH" "$MAPSTORAGE_API_URL/maps")
    EXISTING_COUNT=$(echo "$EXISTING_MAPS" | jq '.maps | length')
    echo "Found $EXISTING_COUNT existing maps"
    echo ""
    
    # Get all map files from GitHub Pages
    echo "🔍 Discovering maps from repository..."
    cd "$(dirname "$0")/../maps" 2>/dev/null || cd maps
    MAPS=($(find . -name "*.tmj" -type f -exec basename {} \;))
    echo "Found ${#MAPS[@]} maps to process"
    echo ""
    
    SUCCESS_COUNT=0
    SKIP_COUNT=0
    ERROR_COUNT=0
    
    # Process each map
    for MAP_FILE in "${MAPS[@]}"; do
        # Generate WAM filename
        WAM_NAME=$(echo "$MAP_FILE" | sed 's/ /-/g' | sed 's/[()]//g' | sed 's/&/and/g' | sed 's/.tmj$/.wam/')
        MAP_URL="${GITHUB_PAGES_BASE_URL}/${MAP_FILE}"
        
        echo -e "📍 Processing: ${YELLOW}$MAP_FILE${NC}"
        echo "   → WAM: $WAM_NAME"
        
        # Check if map already exists
        if echo "$EXISTING_MAPS" | jq -e ".maps.\"$WAM_NAME\"" > /dev/null 2>&1; then
            echo -e "   ${YELLOW}⏭️  SKIP: Already exists${NC}"
            ((SKIP_COUNT++))
        else
            # Create WAM file content
            WAM_CONTENT=$(cat <<EOF
{
  "version": "1.0",
  "mapUrl": "$MAP_URL",
  "entities": {},
  "areas": [],
  "entityCollections": []
}
EOF
)
            
            # Upload to MapStorage
            RESPONSE=$(curl -s -u "$MAPSTORAGE_AUTH" \
                -X PUT \
                -H "Content-Type: application/json" \
                -d "$WAM_CONTENT" \
                "$MAPSTORAGE_API_URL/$WAM_NAME" \
                2>&1)
            
            if echo "$RESPONSE" | grep -q "successfully uploaded"; then
                echo -e "   ${GREEN}✅ SUCCESS${NC}"
                ((SUCCESS_COUNT++))
            else
                echo -e "   ${RED}❌ ERROR: $RESPONSE${NC}"
                ((ERROR_COUNT++))
            fi
        fi
        echo ""
    done
    
    # Summary
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${GREEN}✨ $ENV_NAME Sync Complete!${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${GREEN}✅ Successfully added: $SUCCESS_COUNT${NC}"
    echo -e "${YELLOW}⏭️  Skipped: $SKIP_COUNT${NC}"
    echo -e "${RED}❌ Errors: $ERROR_COUNT${NC}"
    echo "📊 Total maps: ${#MAPS[@]}"
    echo ""
    echo "🔗 View maps at:"
    echo "   $MAPSTORAGE_API_URL/ui/maps"
    echo ""
    
    return 0
}

# Sync to Dev
echo -e "${BLUE}Starting sync to Dev environment...${NC}"
echo ""
if sync_to_environment "DEV" "https://workadventure.dev.dso-os.int.bayer.com/map-storage"; then
    echo -e "${GREEN}✅ Dev sync completed${NC}"
else
    echo -e "${RED}❌ Dev sync failed${NC}"
    exit 1
fi

echo ""
echo "⏳ Waiting 5 seconds before syncing to Staging..."
sleep 5
echo ""

# Sync to Staging
echo -e "${BLUE}Starting sync to Staging environment...${NC}"
echo ""
if sync_to_environment "STAGING" "https://workadventure.staging.dso-os.int.bayer.com/map-storage"; then
    echo -e "${GREEN}✅ Staging sync completed${NC}"
else
    echo -e "${RED}❌ Staging sync failed${NC}"
    exit 1
fi

echo ""
echo "========================================="
echo -e "${GREEN}🎉 Full Sync Complete!${NC}"
echo "========================================="
echo ""
echo "All maps have been synchronized to both environments!"
echo ""
echo "📱 Access your maps:"
echo "  • Dev:     https://workadventure.dev.dso-os.int.bayer.com/"
echo "  • Staging: https://workadventure.staging.dso-os.int.bayer.com/"
echo ""

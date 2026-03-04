#!/bin/bash
# This script spawns workers on the Railway server
# You need to provide your ADMIN_KEY as an argument

if [ -z "$1" ]; then
    echo "Usage: ./spawn_workers_now.sh YOUR_ADMIN_KEY"
    echo ""
    echo "Find your ADMIN_KEY in Railway dashboard → Variables tab"
    exit 1
fi

ADMIN_KEY="$1"
SERVER_URL="https://claim-production-066b.up.railway.app"

echo "Spawning 10 workers on $SERVER_URL..."
echo ""

RESPONSE=$(curl -s -X POST "$SERVER_URL/admin/spawn-workers?count=10" \
  -H "X-Admin-Key: $ADMIN_KEY" \
  -H "Content-Type: application/json")

echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"

echo ""
echo "Done! Restart the game or click 'New Candidates' to see workers."

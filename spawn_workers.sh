#!/bin/bash
# Spawn available workers on the server

SERVER_URL="https://claim-production-066b.up.railway.app"
ADMIN_KEY="your-admin-key-here"  # Replace with actual admin key from .env

echo "Spawning 10 workers on server..."
curl -X POST "$SERVER_URL/admin/spawn-workers?count=10" \
  -H "X-Admin-Key: $ADMIN_KEY" \
  -H "Content-Type: application/json"

echo ""
echo "Done! Workers should now be available for hire."

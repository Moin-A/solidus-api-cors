#!/bin/bash
# Post-deployment script to fix Traefik routing for backend
# Run this after each 'kamal deploy' to ensure correct routing

set -e

SSH_KEY="$HOME/.ssh/kamal-deploy-key.pem"
HOST="ec2-user@13.53.125.253"

echo "🔍 Finding backend container..."
CONTAINER=$(ssh -i "$SSH_KEY" "$HOST" "docker ps --format '{{.Names}}' | grep solidus-api-cors-web | head -1")

if [ -z "$CONTAINER" ]; then
  echo "❌ Backend container not found!"
  exit 1
fi

echo "📦 Found container: $CONTAINER"
echo "⚠️  Note: Docker doesn't allow changing labels on running containers."
echo "💡 The container needs to be recreated with correct labels."
echo ""
echo "🔄 To fix routing, you need to:"
echo "   1. Stop the container: docker stop $CONTAINER"
echo "   2. Remove it: docker rm $CONTAINER"
echo "   3. Recreate it with correct labels (Kamal will do this on next deploy)"
echo ""
echo "📝 Current labels on container:"
ssh -i "$SSH_KEY" "$HOST" "docker inspect $CONTAINER --format '{{range \$k, \$v := .Config.Labels}}{{println \$k \"=\" \$v}}{{end}}' | grep traefik | sort"

echo ""
echo "✅ The issue is that Kamal's proxy section auto-generates labels that override custom ones."
echo "💡 Solution: Remove proxy section and run backend as an accessory, OR use a post-deploy hook."



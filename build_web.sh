#!/bin/bash

# Build script for Time Trak web app (without deployment)
# Use this to build and test locally before deploying

set -e  # Exit on any error

if [ ! -f .env ]; then
  echo "❌ .env not found. Copy .env.example to .env and fill in your Supabase values."
  exit 1
fi


echo "================================"
echo "Time Trak - Web Build (Local)"
echo "================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Step 1: Clean previous builds
echo -e "${BLUE}[1/3] Cleaning previous builds...${NC}"
flutter clean
rm -rf build/web

# Step 2: Get dependencies
echo -e "${BLUE}[2/3] Getting Flutter dependencies...${NC}"
flutter pub get

# Step 3: Build for web
echo -e "${BLUE}[3/3] Building Flutter web app...${NC}"
echo "  - Target: lib/main_web.dart"
echo "  - Renderer: canvaskit"
echo "  - Release mode: Optimized"
echo ""

flutter build web \
  --target=lib/main_web.dart \
  --release \
  --dart-define-from-file=.env \
  --base-href "/"

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}      Build Successful! ✓${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "Build output: build/web/"
echo ""
echo "To test locally, run:"
echo "  cd build/web && python3 -m http.server 8000"
echo "  Then open: http://localhost:8000"
echo ""
echo "To deploy to Firebase, run:"
echo "  ./deploy_web.sh"
echo ""

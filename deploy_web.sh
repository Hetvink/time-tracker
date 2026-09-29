#!/bin/bash

# Firebase Web Deployment Script for Time Trak
# This script builds and deploys the Flutter web app to Firebase Hosting

set -e  # Exit on any error

if [ ! -f .env ]; then
  echo "❌ .env not found. Copy .env.example to .env and fill in your Supabase values."
  exit 1
fi


echo "================================"
echo "Time Trak - Firebase Deployment"
echo "================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Step 1: Clean previous builds
echo -e "${BLUE}[1/4] Cleaning previous builds...${NC}"
flutter clean
rm -rf build/web

# Step 2: Get dependencies
echo -e "${BLUE}[2/4] Getting Flutter dependencies...${NC}"
flutter pub get

# Step 3: Build for web with optimizations
echo -e "${BLUE}[3/4] Building Flutter web app...${NC}"
echo "  - Target: lib/main_web.dart"
echo "  - Renderer: canvaskit (better performance)"
echo "  - Release mode: Optimized and minified"
echo ""

flutter build web \
  --target=lib/main_web.dart \
  --release \
  --dart-define-from-file=.env \
  --base-href "/"

# Step 4: Deploy to Firebase
echo -e "${BLUE}[4/4] Deploying to Firebase Hosting...${NC}"
firebase deploy --only hosting

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}   Deployment Successful! 🚀${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "Your app is now live at:"
echo "https://timetrak-69b32.web.app"
echo ""
echo "To view deployment details:"
echo "  firebase hosting:channel:list"
echo ""

# Firebase Web Deployment Guide

This guide explains how to deploy the Time Trak web application to Firebase Hosting.

## Prerequisites

1. **Firebase CLI**: Already installed at `/usr/local/bin/firebase`
2. **Flutter**: Installed and configured
3. **Firebase Project**: `timetrak-69b32`

## Quick Deployment

To build and deploy in one command:

```bash
./deploy_web.sh
```

This script will:
1. Clean previous builds
2. Get Flutter dependencies
3. Build the web app (optimized for production)
4. Deploy to Firebase Hosting

## Build Only (No Deployment)

To build without deploying:

```bash
./build_web.sh
```

After building, you can test locally:

```bash
cd build/web
python3 -m http.server 8000
```

Then open http://localhost:8000 in your browser.

## Manual Deployment Steps

If you prefer manual control:

### 1. Build the Web App

```bash
flutter build web \
  --target=lib/main_web.dart \
  --web-renderer canvaskit \
  --release \
  --base-href "/"
```

### 2. Deploy to Firebase

```bash
firebase deploy --only hosting
```

## Firebase Hosting Configuration

The deployment is configured in `firebase.json`:

- **Public Directory**: `build/web/`
- **Single Page App**: Yes (all routes redirect to `/index.html`)
- **Caching**: Aggressive caching for static assets (1 year)

## Deployment URLs

After deployment, your app will be available at:

- **Production**: https://timetrak-69b32.web.app
- **Firebase Console**: https://console.firebase.google.com/project/timetrak-69b32

## Environment Variables

Make sure your `.env` file contains the necessary Supabase credentials:

```
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key
```

**Note**: The `.env` file is included in the web build automatically via `pubspec.yaml` assets.

## Web-Specific Features

The web version (`lib/main_web.dart`) includes:

- Web-optimized repositories (WebAttendanceRepository, WebAppActivityRepository)
- Web cache service for performance
- OAuth callback handling for authentication
- Responsive UI using the same MacOS-themed components

## Troubleshooting

### Build Fails

```bash
flutter clean
flutter pub get
flutter build web --target=lib/main_web.dart --web-renderer canvaskit --release
```

### Deployment Fails

Check Firebase login:

```bash
firebase login
firebase projects:list
```

Switch project if needed:

```bash
firebase use timetrak-69b32
```

### Clear Firebase Cache

```bash
rm -rf .firebase/
firebase deploy --only hosting
```

## Monitoring

View deployment history:

```bash
firebase hosting:channel:list
```

View hosting logs:

```bash
firebase hosting:channel:open live
```

## CI/CD Integration

For automated deployments, you can use GitHub Actions with Firebase:

```yaml
# .github/workflows/deploy.yml
name: Deploy to Firebase
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter build web --target=lib/main_web.dart --web-renderer canvaskit --release
      - uses: FirebaseExtended/action-hosting-deploy@v0
        with:
          repoToken: '${{ secrets.GITHUB_TOKEN }}'
          firebaseServiceAccount: '${{ secrets.FIREBASE_SERVICE_ACCOUNT }}'
          projectId: timetrak-69b32
```

## Performance Optimization

The deployment includes:

- CanvasKit renderer for better performance
- Aggressive caching headers (1 year for static assets)
- Minified and tree-shaken code
- Code splitting for faster initial load

## Security

- Environment variables should never be committed
- OAuth credentials are configured in Firebase Console
- Supabase RLS (Row Level Security) protects data access

#!/bin/bash

# Time Trak - macOS DMG Builder
# This script creates a DMG installer with proper code signing and notarization

set -e

echo "🚀 Building Time Trak for macOS..."

# Configuration
APP_NAME="time_trak"
DISPLAY_NAME="Time Trak"
DMG_NAME="TimeTracking-Installer"
BUILD_DIR="build/macos/Build/Products/Release"
DMG_DIR="build/dmg"
VOLUME_NAME="TimeTracking Installer"






# Code Signing Configuration
# Set these environment variables or create a .env.signing file
# DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAM_ID)"
# DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAM_ID)"
# APPLE_ID="your-apple-id@email.com"
# APPLE_ID_PASSWORD="app-specific-password"
# TEAM_ID="YOUR_TEAM_ID"

# Load signing configuration if available
if [ -f ".env.signing" ]; then
    echo "📝 Loading signing configuration..."
    source .env.signing
fi

# Check if we should sign the app
SHOULD_SIGN=false
SIGN_TYPE="none"
if [ -n "$DEVELOPER_ID_APPLICATION" ]; then
    SHOULD_SIGN=true
    # Check if it's a Developer ID (from Apple) or self-signed
    if [[ "$DEVELOPER_ID_APPLICATION" == *"Developer ID Application"* ]]; then
        SIGN_TYPE="developer_id"
        echo "✅ Code signing enabled (Apple Developer ID)"
    else
        # Fallback to ad-hoc for self-signed/other certs to prevent SIGKILL/AMFI issues
        SIGN_TYPE="adhoc"
        echo "⚠️  Non-standard identity found - falling back to Ad-Hoc signing"
        echo "   (This ensures the App runs locally without issues)"
    fi
else
    SIGN_TYPE="adhoc"
    SHOULD_SIGN=true
    echo "⚠️  No Developer ID found - using Ad-Hoc signing"
    echo "   (Required for ARM Macs to run locally)"
fi

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Build the app
echo "🆙 Incrementing version..."
dart scripts/increment_version.dart

echo "🔨 Building Flutter app..."
flutter build macos \
  --release \
  --dart-define-from-file=.env \
  --dart-define=dart.vm.product=true \
  --split-debug-info=build/macos-debug-info \
  --obfuscate

# Check if build was successful
if [ ! -d "$BUILD_DIR/$APP_NAME.app" ]; then
    echo "❌ Build failed - app not found at $BUILD_DIR/$APP_NAME.app"
    exit 1
fi

echo "✅ Build successful!"

# Copy app to DMG directory
echo "📦 Preparing DMG contents..."
cp -R "$BUILD_DIR/$APP_NAME.app" "$DMG_DIR/$DISPLAY_NAME.app"

# EXECUTION PERMISSION FIX:
# Ensure the main executable has the correct permissions
EXECUTABLE_PATH="$DMG_DIR/$DISPLAY_NAME.app/Contents/MacOS/$APP_NAME"
if [ -f "$EXECUTABLE_PATH" ]; then
    echo "🔧 Fixing executable permissions..."
    chmod +x "$EXECUTABLE_PATH"
else
    echo "❌ Error: Executable not found at $EXECUTABLE_PATH"
    echo "   Check if APP_NAME matches the actual binary name."
    exit 1
fi

# Code sign the app if configured
if [ "$SHOULD_SIGN" = true ]; then
    echo "🔐 Code signing application..."

    # Sign all frameworks and dylibs first
    find "$DMG_DIR/$DISPLAY_NAME.app/Contents/Frameworks" -name "*.dylib" -o -name "*.framework" | while read framework; do
        echo "  Signing: $(basename "$framework")"
        codesign --force --deep --timestamp \
            --options runtime \
            --sign "$DEVELOPER_ID_APPLICATION" \
            "$framework" 2>/dev/null || true
    done


    # Sign the main app bundle
    echo "  Signing main app bundle..."
    
    if [ "$SIGN_TYPE" = "adhoc" ]; then
        # Ad-hoc signing (for local development/testing)
        # Note: We DO NOT include entitlements here because ad-hoc signing
        # with restricted entitlements (like keychain-access-groups) causes
        # SIGKILL/launch failure without a valid provisioning profile.
        codesign --force --deep \
            --sign - \
            "$DMG_DIR/$DISPLAY_NAME.app"
        echo "✅ Ad-hoc signed (runs on this machine)"
    elif [ "$SIGN_TYPE" = "self_signed" ]; then
        # Self-signed (now falls back to ad-hoc/no-entitlements to avoid SIGKILL)
        codesign --force --deep \
            --sign - \
            "$DMG_DIR/DISPLAY_NAME.app"
        echo "✅ Self-signed (Ad-Hoc mode, no entitlements)"
    else
        # Proper Developer ID signing
        codesign --force --deep --timestamp \
            --options runtime \
            --entitlements "macos/Runner/Release.entitlements" \
            --sign "$DEVELOPER_ID_APPLICATION" \
            "$DMG_DIR/$DISPLAY_NAME.app"
    fi

    # Verify signature
    echo "✅ Verifying signature..."
    codesign --verify --verbose "$DMG_DIR/$DISPLAY_NAME.app"
    if [ "$SIGN_TYPE" != "adhoc" ]; then
        spctl --assess --verbose "$DMG_DIR/$DISPLAY_NAME.app" || echo "⚠️  App not yet notarized"
    fi
else
    echo "❌ Error: Should not reach here - signing is enforced (adhoc minimum)"
fi

# Create Applications folder symlink
echo "🔗 Creating Applications folder symlink..."
ln -s /Applications "$DMG_DIR/Applications"

# Create a background image directory (optional)
mkdir -p "$DMG_DIR/.background"

# Create DMG
echo "💿 Creating DMG..."
DMG_PATH="build/$DMG_NAME.dmg"

# Remove old DMG if exists
rm -f "$DMG_PATH"

# Create temporary DMG
hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

# Sign the DMG if configured
if [ "$SHOULD_SIGN" = true ] && [ -n "$DEVELOPER_ID_APPLICATION" ] && [ "$SIGN_TYPE" != "adhoc" ]; then
    echo "🔐 Signing DMG..."
    codesign --force --timestamp \
        --sign "$DEVELOPER_ID_APPLICATION" \
        "$DMG_PATH"
elif [ "$SHOULD_SIGN" = true ] && [ "$SIGN_TYPE" = "adhoc" ]; then
    echo "⚠️  Skipping DMG signing (Ad-Hoc mode - no Developer ID available)"
    echo "   DMG is ready for local use"
else
    echo "⚠️  Skipping DMG signing (no Developer ID available)"
    echo "   DMG is ready for local use"
fi

echo "✅ DMG created successfully at: $DMG_PATH"
echo ""
echo "📋 Installation Instructions:"
echo "1. Open the DMG file"
echo "2. Drag 'Time Trak.app' to the 'Applications' folder"
echo "3. Eject the DMG"
echo "4. Open Time Trak from Applications folder"
echo ""
echo "📂 Copying DMG to Desktop..."
cp "$DMG_PATH" "$HOME/Desktop/$DMG_NAME.dmg"
echo "✅ DMG saved to Desktop: $HOME/Desktop/$DMG_NAME.dmg"
echo ""

# Notarization (if configured)
if [ "$SHOULD_SIGN" = true ] && [ -n "$APPLE_ID" ] && [ -n "$APPLE_ID_PASSWORD" ]; then
    echo "📤 Submitting for notarization..."
    echo "   This may take several minutes..."

    # Submit for notarization
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    # Staple the notarization ticket
    echo "📎 Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler staple "$HOME/Desktop/$DMG_NAME.dmg"

    echo "✅ App is notarized and ready for distribution!"
elif [ "$SHOULD_SIGN" = true ]; then
    echo "⚠️  App is signed but not notarized"
    echo "   To notarize, set APPLE_ID, APPLE_ID_PASSWORD, and TEAM_ID in .env.signing"
    echo "   Without notarization, users will see a warning on first launch"
fi

echo ""
echo "🎉 Done!"
echo ""

# Print signing status
if [ "$SHOULD_SIGN" = true ]; then
    if [ -n "$APPLE_ID" ]; then
        echo "✅ Status: Signed and Notarized - Ready for distribution to any Mac"
        echo "   No user intervention needed - app will open without warnings!"
    elif [ "$SIGN_TYPE" = "self_signed" ]; then
        echo "✅ Status: Self-Signed (FREE) - Good for internal distribution"
        echo "   Users need to click 'Open Anyway' once (one-time approval)"
        echo "   See SELF_SIGNED_CODESIGNING.md for employee instructions"
    else
        echo "⚠️  Status: Signed but not notarized - Users will see a warning"
        echo "   Users need to click 'Open Anyway' once (one-time approval)"
        echo "   To notarize, set APPLE_ID, APPLE_ID_PASSWORD, and TEAM_ID in .env.signing"
    fi
else
    echo "⚠️  Status: Unsigned - Will only work with security settings disabled"
    echo "   Users must go to: System Settings > Privacy & Security > Allow Anyway"
    echo ""
    echo "   Options to fix:"
    echo "   1. FREE: Self-signed certificate (see SELF_SIGNED_CODESIGNING.md)"
    echo "   2. \$99/year: Apple Developer ID (see SETUP_CODESIGNING.md)"
fi

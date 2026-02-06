# Build the Xcode project
build:
    xcodebuild -project ClawDaddy/ClawDaddy.xcodeproj -scheme ClawDaddy -configuration Debug -derivedDataPath /tmp/crawdaddy-derived build

# Build a release archive
archive:
    xcodebuild -project ClawDaddy/ClawDaddy.xcodeproj -scheme ClawDaddy -configuration Release -archivePath /tmp/crawdaddy-release/ClawDaddy.xcarchive archive

# Export a signed .app from archive (requires ClawDaddy/ExportOptions.plist)
export-app:
    xcodebuild -exportArchive -archivePath /tmp/crawdaddy-release/ClawDaddy.xcarchive -exportPath /tmp/crawdaddy-release/export -exportOptionsPlist ClawDaddy/ExportOptions.plist

# Build a distributable DMG from exported app
package-dmg:
    rm -rf /tmp/crawdaddy-release/dmg-root /tmp/crawdaddy-release/ClawDaddy.dmg
    mkdir -p /tmp/crawdaddy-release/dmg-root
    cp -R /tmp/crawdaddy-release/export/ClawDaddy.app /tmp/crawdaddy-release/dmg-root/
    hdiutil create -volname "ClawDaddy" -srcfolder /tmp/crawdaddy-release/dmg-root -ov -format UDZO /tmp/crawdaddy-release/ClawDaddy.dmg

# Notarize the DMG using a configured keychain profile
notarize-dmg:
    xcrun notarytool submit /tmp/crawdaddy-release/ClawDaddy.dmg --keychain-profile "$NOTARY_PROFILE" --wait

# Staple notarization ticket to exported app and DMG
staple:
    xcrun stapler staple /tmp/crawdaddy-release/export/ClawDaddy.app
    xcrun stapler staple /tmp/crawdaddy-release/ClawDaddy.dmg

# Run macOS unit tests
test-macos:
    xcodebuild test -project ClawDaddy/ClawDaddy.xcodeproj -scheme ClawDaddy -destination 'platform=macOS' -derivedDataPath /tmp/crawdaddy-derived -only-testing:ClawDaddyTests

# Run macOS UI tests (requires interactive permissions)
test-macos-ui:
    xcodebuild test -project ClawDaddy/ClawDaddy.xcodeproj -scheme ClawDaddy -destination 'platform=macOS' -derivedDataPath /tmp/crawdaddy-derived -only-testing:ClawDaddyUITests

# Check all Swift files parse correctly
check-swift:
    swiftc -parse -target arm64-apple-macosx14.0 -sdk $(xcrun --show-sdk-path) ClawDaddy/ClawDaddy/**/*.swift

# Run release-oriented checks
check: check-swift test-macos

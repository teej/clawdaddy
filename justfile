# Build the Xcode project
build:
    xcodebuild -project ClawDaddy/ClawDaddy.xcodeproj -scheme ClawDaddy -configuration Debug -derivedDataPath /tmp/crawdaddy-derived build

# Run macOS unit tests
test-macos:
    xcodebuild test -project ClawDaddy/ClawDaddy.xcodeproj -scheme ClawDaddy -destination 'platform=macOS' -derivedDataPath /tmp/crawdaddy-derived -only-testing:ClawDaddyTests

# Run macOS UI tests (requires interactive permissions)
test-macos-ui:
    xcodebuild test -project ClawDaddy/ClawDaddy.xcodeproj -scheme ClawDaddy -destination 'platform=macOS' -derivedDataPath /tmp/crawdaddy-derived -only-testing:ClawDaddyUITests

# Check all Swift files parse correctly
check-swift:
    swiftc -parse -target arm64-apple-macosx14.0 -sdk $(xcrun --show-sdk-path) ClawDaddy/ClawDaddy/**/*.swift

# Run backend Python tests
test-backend:
    uv run --extra test pytest backend/tests/ -q

# Run backend tests with deprecations treated as errors
test-backend-strict:
    uv run --extra test pytest backend/tests/ -q -W error::DeprecationWarning

# Run both checks
check: check-swift test-backend-strict

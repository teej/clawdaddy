# Build the Xcode project
build:
    xcodebuild -project ClawDaddy/ClawDaddy.xcodeproj -scheme ClawDaddy -configuration Debug build

# Check all Swift files parse correctly
check-swift:
    swiftc -parse -target arm64-apple-macosx14.0 -sdk $(xcrun --show-sdk-path) ClawDaddy/ClawDaddy/**/*.swift

# Run backend Python tests
test-backend:
    uv run pytest backend/tests/

# Run both checks
check: check-swift test-backend

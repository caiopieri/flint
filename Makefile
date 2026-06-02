# Flint — developer entry points. See docs/TASKS.md.

.PHONY: bootstrap web generate build open clean

# One-time setup: web deps + bundle + generate the Xcode project.
bootstrap:
	./scripts/bootstrap.sh

# Build just the web runtime bundle and copy it into the app resources.
web:
	./scripts/build-web.sh

# (Re)generate ios/Flint.xcodeproj from project.yml.
generate:
	cd ios && xcodegen generate

# Build the app for the iOS Simulator (no code signing).
build: web generate
	cd ios && xcodebuild \
		-project Flint.xcodeproj \
		-scheme Flint \
		-destination 'generic/platform=iOS Simulator' \
		-configuration Debug \
		CODE_SIGNING_ALLOWED=NO \
		build

# Open the project in Xcode.
open: generate
	open ios/Flint.xcodeproj

clean:
	rm -rf ios/Flint.xcodeproj web/dist web/node_modules
	find ios/Flint/Resources/web -mindepth 1 ! -name '.gitkeep' -delete

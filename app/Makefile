# =============================================================================
# Makefile — FreeVoice Swift app helper commands
# =============================================================================
# Install xcodegen first:  brew install xcodegen
# =============================================================================

.PHONY: generate open build clean

## generate: (Re)create FreeVoice.xcodeproj from project.yml
generate:
	xcodegen generate

## open: Regenerate project and open in Xcode
open: generate
	open FreeVoice.xcodeproj

## build: Build Debug configuration from the command line (requires Xcode CLT)
build: generate
	xcodebuild -project FreeVoice.xcodeproj \
	           -scheme FreeVoice \
	           -configuration Debug \
	           -derivedDataPath DerivedData \
	           build

## clean: Remove generated Xcode project and build artefacts
clean:
	rm -rf FreeVoice.xcodeproj DerivedData build

# =============================================================================
# Makefile — FreeVoice Swift app helper commands
# =============================================================================
# Install xcodegen first:  brew install xcodegen
# =============================================================================

.PHONY: generate open build clean reset-access archive export notarize dmg

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

## reset-access: Clear Accessibility TCC entry (run after each Xcode rebuild during dev)
## After running: stop app in Xcode → ⌘R → grant in System Settings → stop → ⌘R
reset-access:
	tccutil reset Accessibility com.freevoice.app

# =============================================================================
# Distribution targets (Phase 5)
# =============================================================================

## archive: Build Release archive → build/FreeVoice.xcarchive
archive: generate
	xcodebuild archive \
	    -project FreeVoice.xcodeproj \
	    -scheme FreeVoice \
	    -configuration Release \
	    -archivePath build/FreeVoice.xcarchive \
	    | xcpretty || true

## export: Export Developer ID-signed .app → build/export/FreeVoice.app
export:
	xcodebuild -exportArchive \
	    -archivePath build/FreeVoice.xcarchive \
	    -exportOptionsPlist ExportOptions.plist \
	    -exportPath build/export/

## notarize: Submit to Apple notarization, wait for result, then staple
## Prerequisite: run `xcrun notarytool store-credentials "FreeVoice"` once first
notarize:
	ditto -c -k --keepParent build/export/FreeVoice.app build/FreeVoice-notarize.zip
	xcrun notarytool submit build/FreeVoice-notarize.zip \
	    --keychain-profile "FreeVoice" \
	    --wait
	xcrun stapler staple build/export/FreeVoice.app
	rm build/FreeVoice-notarize.zip

## dmg: Create distributable DMG → build/FreeVoice.dmg
dmg:
	mkdir -p build/dmg
	cp -R build/export/FreeVoice.app build/dmg/
	ln -sf /Applications build/dmg/Applications
	hdiutil create \
	    -volname "FreeVoice" \
	    -srcfolder build/dmg/ \
	    -ov -format UDZO \
	    build/FreeVoice.dmg
	rm -rf build/dmg
	@echo "DMG ready: build/FreeVoice.dmg"

## dist: Full distribution pipeline (archive → export → notarize → dmg)
dist: archive export notarize dmg

# Release Process

This document covers how to build, sign, notarize, and ship a new version of FreeVoice.

---

## Prerequisites

- Xcode 15+
- `xcodegen`: `brew install xcodegen`
- Apple Developer ID Application certificate in Keychain
- `notarytool` credentials stored as keychain profile `"notarytool"`
  (set up once with `xcrun notarytool store-credentials "notarytool"`)
- Sparkle private EdDSA key in Keychain (generated once, see below)

---

## 1. Bump the Version

In `app/project.yml`, update both fields:

```yaml
CFBundleShortVersionString: "1.2.1"   # human-readable version
CFBundleVersion: "11"                  # integer, increment by 1 each release
```

---

## 2. Regenerate and Build

```bash
cd app
xcodegen generate
xcodebuild -scheme FreeVoice -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=TEAMID \
  clean build
```

---

## 3. Re-sign for Notarization

The release build includes a debug entitlement (`get-task-allow`) that must be stripped:

```bash
# Release entitlements (no get-task-allow)
cat > /tmp/freevoice-release.entitlements << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
EOF

APP="build/Build/Products/Release/FreeVoice.app"

# Find your cert hash (use the one that isn't expired):
security find-identity -v -p codesigning | grep "Developer ID Application"

# Re-sign using the hash shown above
codesign --force --deep --timestamp --options runtime \
  --sign "CERT_HASH_HERE" \
  --entitlements /tmp/freevoice-release.entitlements \
  "$APP"
```

---

## 4. Create DMG

```bash
hdiutil create -volname "FreeVoice" \
  -srcfolder "build/Build/Products/Release/FreeVoice.app" \
  -ov -format UDZO \
  "../FreeVoice-1.2.1.dmg"
```

---

## 5. Notarize and Staple

```bash
xcrun notarytool submit "../FreeVoice-1.2.1.dmg" \
  --keychain-profile "notarytool" --wait

xcrun stapler staple "../FreeVoice-1.2.1.dmg"
```

---

## 6. Sign the DMG for Sparkle

Sparkle requires each release artifact to be signed with your EdDSA private key
(stored in macOS Keychain — see "Sparkle Keys" below):

```bash
SPARKLE_TOOLS=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" 2>/dev/null | head -1)
"$SPARKLE_TOOLS" "../FreeVoice-1.2.1.dmg"
```

This outputs a signature like:
```
sparkle:edSignature="ABC123..." length="12345678"
```

Save this — you'll need it in the appcast.

---

## 7. Create / Update the Appcast

Host `appcast.xml` at `https://charlesintro.com/freevoice/appcast.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>FreeVoice</title>
    <link>https://charlesintro.com/freevoice/appcast.xml</link>
    <item>
      <title>FreeVoice 1.2.1</title>
      <pubDate>Mon, 24 Mar 2026 00:00:00 +0000</pubDate>
      <sparkle:version>11</sparkle:version>
      <sparkle:shortVersionString>1.2.1</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/charlesintro/freevoice/releases/download/v1.2.1/FreeVoice-1.2.1.dmg"
        sparkle:edSignature="SIGNATURE_FROM_STEP_6"
        length="LENGTH_FROM_STEP_6"
        type="application/octet-stream"
      />
    </item>
  </channel>
</rss>
```

Add a new `<item>` block for each release. Keep older items so users on older versions
can still update.

---

## 8. Create GitHub Release

```bash
gh release create v1.2.1 FreeVoice-1.2.1.dmg \
  --title "FreeVoice v1.2.1" \
  --notes "Release notes here"
```

The website download link (`/releases/latest`) updates automatically.

---

## Sparkle Keys

### How they were generated (one-time, already done)

```bash
# Path to Sparkle tools inside Xcode DerivedData
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -name "generate_keys" 2>/dev/null | head -1)
"$SPARKLE_BIN"
```

This generated an EdDSA key pair and stored the **private key in macOS Keychain**.
The **public key** (`yfkA4qYp2qOsC1gKRfX33iNKMBNOfqRd5Pv2LJJcMy0=`) is in `app/project.yml`
as `SUPublicEDKey` — safe to commit, must be public.

### Backup warning

The **private signing key lives only in your macOS Keychain**. If you lose it
(new Mac, wiped machine), you cannot sign future updates and existing users will
have to manually download a new DMG.

**Back it up now:**

```bash
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -name "generate_keys" 2>/dev/null | head -1)
"$SPARKLE_BIN" --export
```

Store the output somewhere safe (password manager, encrypted backup).

---

## Code Signing Notes

There are two Developer ID Application certificates in Keychain (one may be expired
or a duplicate). When signing, use the hash of the valid/current one:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

Use the SHA-1 hash directly in the `--sign` flag to avoid ambiguity errors.
Clean up the expired cert via **Keychain Access** when convenient.

---

## Checklist

- [ ] Bump `CFBundleShortVersionString` and `CFBundleVersion` in `project.yml`
- [ ] `xcodegen generate`
- [ ] Release build succeeds
- [ ] Re-signed without `get-task-allow`
- [ ] DMG created
- [ ] Notarized and stapled
- [ ] DMG signed with `sign_update` (Sparkle)
- [ ] `appcast.xml` updated on charlesintro.com
- [ ] GitHub release created with DMG attached
- [ ] Commit + push source changes

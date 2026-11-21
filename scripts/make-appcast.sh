#!/bin/bash
# Signs a release zip with the Sparkle EdDSA key and writes build/appcast.xml for it.
#
# usage: SPARKLE_PRIVATE_KEY=... scripts/make-appcast.sh <zip> <version> <build> <tag>
# The key comes from $SPARKLE_PRIVATE_KEY (CI secret) or, if unset, from the login Keychain
# (account "icon-picker", created with: generate_keys --account icon-picker).
set -euo pipefail
cd "$(dirname "$0")/.."

ZIP="$1" VERSION="$2" BUILD="$3" TAG="$4"
REPO="${GITHUB_REPOSITORY:-ahamedzoha/icon-picker}"
SIGN=".build/artifacts/sparkle/Sparkle/bin/sign_update"

if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  ATTRS="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN" --ed-key-file - "$ZIP")"
else
  ATTRS="$("$SIGN" --account icon-picker "$ZIP")"
fi

URL="https://github.com/$REPO/releases/download/$TAG/$(basename "$ZIP")"
DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
MIN="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"

cat > build/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Icon Picker</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Version $VERSION</title>
      <link>https://github.com/$REPO/releases/tag/$TAG</link>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN</sparkle:minimumSystemVersion>
      <enclosure url="$URL" type="application/octet-stream" $ATTRS />
    </item>
  </channel>
</rss>
EOF
echo "Wrote build/appcast.xml for $VERSION ($BUILD)"

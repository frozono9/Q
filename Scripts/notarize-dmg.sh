#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: Q_NOTARY_PROFILE=<profile> $0 path/to/Q.dmg" >&2
    exit 1
fi

dmg=$1
profile=${Q_NOTARY_PROFILE:-}
if [ ! -f "$dmg" ]; then
    echo "Missing disk image: $dmg" >&2
    exit 1
fi
if [ -z "$profile" ]; then
    echo "Set Q_NOTARY_PROFILE to a notarytool Keychain profile." >&2
    echo "Create one with: xcrun notarytool store-credentials <profile>" >&2
    exit 1
fi

xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

echo "$dmg"


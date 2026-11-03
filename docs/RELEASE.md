# Sending Snapr to other people

Other Macs only open Snapr without warnings when it is signed with a
Developer ID certificate and notarized by Apple. That needs a paid Apple
Developer Program membership.

## Once

1. Xcode > Settings > Accounts > your team > Manage Certificates > `+` >
   **Developer ID Application**. (Apple Development certificates do not work
   for other Macs.)
2. Check it: `security find-identity -v -p codesigning` lists it.
3. Make an app-specific password at account.apple.com, then:
   `xcrun notarytool store-credentials snapr-notary --apple-id <email> --team-id <TEAMID>`

## Each release

1. Raise `CFBundleShortVersionString` in `Info.plist.in`.
2. `tools/release.sh` writes `dist/Snapr.zip`, signed and notarized.
3. Send the zip. They unzip it and drag Snapr to Applications.

## Without a paid account

Share an ad hoc build (`./build.sh`). On the other Mac, the first open is
blocked: right-click Snapr > Open, or run
`xattr -dr com.apple.quarantine /Applications/Snapr.app`.
Each person also grants Screen Recording themselves.

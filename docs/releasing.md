# Releasing Kol

`scripts/release.sh` builds a Developer ID signed app, submits it to Apple's
notary service, and staples the notarization ticket before publishing the ZIP
on GitHub. A rejected submission, missing ticket, or failed Gatekeeper check
stops the release before the version commit, tag, or push.

## One-time setup

Install Xcode, `xcodebuildmcp`, Bun, and the GitHub CLI. Authenticate `gh` with
access to the repository. Import a Developer ID Application certificate and
its private key into the login Keychain.

Store notarization credentials in Keychain:

```bash
xcrun notarytool store-credentials "kol-notary"
```

At `Path to App Store Connect API private key:`, press Enter to leave the field
blank and use an Apple Account. At `Developer Apple ID:`, enter the email used
to sign in to the Apple Developer account. The command also prompts for an
app-specific password and the Developer Program team ID. Use the team that
issued the signing certificate.
Create the app-specific password at <https://account.apple.com>. The command
validates the credentials before saving them. Keep credentials out of repository
files and shell command arguments.

Generate the Sparkle update-signing key once on your release Mac:

```bash
SPARKLE_TOOLS=$(./scripts/sparkle-tools.sh)
"$SPARKLE_TOOLS/generate_keys" --account kol-updates
```

The command saves the private key in the login Keychain and prints the public
key. Put that public key in `SUPublicEDKey` in `Kol/Info.plist`. When macOS asks
for `generate_appcast` or `sign_update` to access the Sparkle private key, approve
that system dialog. Enter your Mac password only in the system dialog. Keep the original
private key for every future release. On a Mac with the existing key, the command
reuses that key. The release script rejects a missing key or a public-key mismatch
before changing version metadata.

To back up the private key, use `generate_keys --account kol-updates -x` with a
file path in secure storage outside the repository. Import the backup on another
release Mac with `generate_keys --account kol-updates -f` and the backup path.
Never commit the backup. Notarization credentials and the Sparkle signing key
are separate Keychain entries.

## Run a release

Commit the changes and their changeset fragments, then run from `main`:

```bash
./scripts/release.sh <major.minor.patch>
```

The script checks Keychain credentials before changing version metadata. It
collects changesets, runs the tests, and calls `build-install.sh --release`.
Xcode signs the app and nested code with secure timestamps and the hardened
runtime, preserving each target's entitlements. The distribution build is not
installed in `/Applications`.

The script waits up to an hour for notarization. After Apple accepts the
submission, the script staples and validates the ticket, verifies the signature,
and checks Gatekeeper. It creates a fresh ZIP containing the stapled app and
extracts the ZIP to verify that the ticket and signature survived packaging.
The script then commits and tags the version, pushes, uploads a draft release,
verifies both uploaded artifacts' SHA-256 digests, and publishes the release.
Before the version commit, Sparkle signs the final ZIP and generates a signed
`appcast.xml` with embedded release notes. The script verifies both signatures
and confirms that the feed names the exact version, build, download URL, and ZIP
size. Every release includes its feed alongside the ZIP.

Kol checks `https://github.com/alandotcom/Kol/releases/latest/download/appcast.xml`.
The feed links to the ZIP on that specific version's release. Users install the
first release containing Sparkle manually. Later releases update in place.
Kol enables automatic checks and downloads by default and installs downloaded
updates when the app quits. Users can change both preferences under
**Settings → General → Updates** or use **Check for Updates** in Kol's menu.
An update restart waits for active dictation and text insertion to finish.
Debug builds do not run the updater.

Keep the app's bundle identifier, sandbox setting, and signing team unchanged
across releases so existing settings and models remain in the same container.

These environment variables override the defaults:

- `KOL_NOTARY_PROFILE`: Keychain profile name, default `kol-notary`.
- `KOL_SIGNING_IDENTITY`: Developer ID Application certificate name or SHA-1
  fingerprint. The default selects a `Developer ID Application` identity. Set
  this variable if the Keychain contains multiple matching certificates.
- `KOL_SIGNING_TEAM`: Developer Program team ID, default the team in the Xcode
  project. Xcode applies this team to package dependencies as well as app targets.
- `KOL_NOTARY_TIMEOUT`: notarization wait limit, default `1h`.
- `KOL_DERIVED_DATA_PATH`: Xcode build directory, default `build/DerivedData`.
- `KOL_SPARKLE_ACCOUNT`: update-signing Keychain account, default `kol-updates`.
- `KOL_SPARKLE_TOOLS`: directory containing `generate_keys`, `generate_appcast`,
  and `sign_update`. By default, `sparkle-tools.sh` downloads Sparkle 2.10.0 tools
  and verifies the archive's pinned SHA-256 digest.

Local testing still uses `./scripts/build-install.sh --debug`. Notarization runs
only through the release script.

## Failed notarization

Verification files are in `build/verification/release-<version>/`. Inspect
`notarization.json`, `notarization-stderr.log`, and `notarization-log.json` for
the submission ID, status, and Apple's diagnostics. The diagnostic log may be
unavailable while Apple is still processing a submission.

If the wait times out, Apple continues processing. Use the saved submission ID
and the same Keychain profile to check the status:

```bash
xcrun notarytool info <submission-id> --keychain-profile "kol-notary"
xcrun notarytool log <submission-id> --keychain-profile "kol-notary" notarization-log.json
```

Release preparation leaves version and changelog edits in the working tree if
a later step fails. Inspect those edits before restoring the previous metadata
and changeset fragments for a fresh run. The script requires a clean working
tree and does not automatically resume a failed release.

Apple documents the prerequisites in
[Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Verify script changes

```bash
bash -n scripts/build-install.sh scripts/release.sh scripts/sparkle-tools.sh scripts/sign-sparkle.sh
shellcheck scripts/build-install.sh scripts/release.sh scripts/sparkle-tools.sh scripts/sign-sparkle.sh
python3 -m unittest discover -s scripts/tests
```

The script tests use isolated fixtures and stand-ins for Apple and GitHub
commands. They never upload software, publish a release, or modify installed apps.

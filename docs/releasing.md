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
verifies the upload's SHA-256 digest, and publishes it.

These environment variables override the defaults:

- `KOL_NOTARY_PROFILE`: Keychain profile name, default `kol-notary`.
- `KOL_SIGNING_IDENTITY`: Developer ID Application certificate name or SHA-1
  fingerprint. The default selects a `Developer ID Application` identity. Set
  this variable if the Keychain contains multiple matching certificates.
- `KOL_SIGNING_TEAM`: Developer Program team ID, default the team in the Xcode
  project. Xcode applies this team to package dependencies as well as app targets.
- `KOL_NOTARY_TIMEOUT`: notarization wait limit, default `1h`.
- `KOL_DERIVED_DATA_PATH`: Xcode build directory, default `build/DerivedData`.

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
bash -n scripts/build-install.sh scripts/release.sh
shellcheck scripts/build-install.sh scripts/release.sh
python3 -m unittest discover -s scripts/tests
```

The script tests use isolated fixtures and stand-ins for Apple and GitHub
commands. They never upload software, publish a release, or modify installed apps.

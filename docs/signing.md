# Developer ID signing and automated releases

LeftBlank distributes a macOS arm64 app ZIP directly, outside the Mac App Store, using a **Developer ID Application** identity. The app and bundled helpers use hardened runtime and secure timestamps. Apple notarization, ticket stapling and Gatekeeper validation must succeed before the public release ZIP is produced.

## One-time setup

Signing in to Xcode locally does not give a GitHub runner signing credentials. The repository requires:

| GitHub setting | Value |
|---|---|
| Secret `SIGNING_CERTIFICATE_P12` | Base64-encoded `.p12` containing the Developer ID Application private key |
| Secret `SIGNING_CERTIFICATE_PASSWORD` | Password used to export the `.p12` |
| Secret `APP_STORE_CONNECT_PRIVATE_KEY` | Dedicated App Store Connect Team API `.p8` private key |
| Secret `APP_STORE_CONNECT_KEY_ID` | API key ID |
| Secret `APP_STORE_CONNECT_ISSUER_ID` | Team API issuer ID |
| Variable `APPLE_TEAM_ID` | The certificate's developer team ID |
| Secret `ICLOUD_PROVISIONING_PROFILE` | Base64 Developer ID profile authorizing LeftBlank's iCloud container and KVS |

Create the certificate through Xcode → Settings → Apple Accounts → team → Manage Certificates → Developer ID Application. Create the API key under App Store Connect → Users and Access → Integrations, with the least privilege needed for notarization. The private key can be downloaded once; store it in a password manager or protected file, never an issue, PR or chat.

Supply secrets to `gh secret set --repo leftblank-app/leftblank NAME` through stdin rather than expanding values in command arguments or logs. Certificates and private keys do not belong in source or build artifacts.

The previous Sumi testing identity and profile were configured on 2026-10-01. Before releasing LeftBlank, register and associate the `app.leftblank.writer` App ID and dedicated `iCloud.app.leftblank.writer` container, then download and validate a matching Developer ID profile and replace the repository secret. `prepare-icloud-profile.py` checks team, App ID, certificate membership, expiration, distribution scope and required capabilities, then emits only the required entitlements. The release embeds the profile and verifies the signed entitlements. Helper processes do not receive iCloud entitlements. Local development builds remain ad hoc and cannot use iCloud. LeftBlank Preview is Developer ID signed, but intentionally has no production iCloud entitlement or profile.

The new LeftBlank identity still requires portal configuration, CI-secret replacement, a release run and native account/two-Mac verification. The prior notarization result below predates this capability.

## Verification and publication

1. PR CI runs functional tests, coverage, large-book benchmarks and distribution-isolation checks without release credentials. After successful main CI, a separate job creates a Developer ID signed and notarized LeftBlank Preview package, uploads it for seven days, and publishes its signed update feed. See [Preview updates](preview-updates.md).
2. A manual Release workflow on main verifies signing and notarization and saves an artifact without creating a public Release.
3. Update the version and build number in `Resources/Info.plist`, then merge the verified commit into main.
4. Push a matching version tag, such as `v0.3.0`. The workflow checks that main contains the tagged commit, runs functional tests and the 80% coverage gate, then signs, notarizes, staples and publishes.

Missing credentials, invalid certificates, team mismatch, rejected notarization or timeout stop public publication. There is no fallback to development signing. The temporary signing keychain joins the search list so codesign can locate the identity and chain. Cleanup restores the old list and removes the temporary keychain, certificate and API key. Notarization submission results remain available for investigation; private keys are never uploaded as artifacts.

Development builds use `scripts/build.sh release`. Set `LEFTBLANK_DISTRIBUTION=preview` to package `build/LeftBlank Preview.app`; `LEFTBLANK_BUILD_NUMBER` must be an increasing `run_number.run_attempt` for published builds. `scripts/release.sh` requires the settings above. Local temporary release material stays on the external SSD.

## Completed verification

On 2026-10-01, before the LeftBlank rename, all release credentials were configured for `fenjin-ai/sumi`, and [a manual release run](https://github.com/leftblank-app/leftblank/actions/runs/36824914236) passed on commit `72f7d8e`, app version **0.2.0**, build **3**. This generated an Actions artifact only, without a public tag or Release.

- 36 functional and integration tests passed; production coverage was 88.57%, above the 80% gate.
- The arm64 app and Tinymist helper were signed by `Developer ID Application: Fenjin Wang (X6BK42MX95)` with hardened runtime and secure timestamps. The certificate expires on 2031-09-17.
- Apple submission `ae76e6c3-2354-4259-8e60-7e6411c5271c` returned `Accepted`, and its ticket was stapled.
- An independently downloaded final ZIP passed SHA-256, `codesign --verify --deep --strict`, `stapler validate` and Gatekeeper (`source=Notarized Developer ID`). The signed Tinymist helper ran successfully.

That run's `release-macos-15` artifact contains `Sumi-0.2.0-macOS-arm64.zip` and its `.sha256`. Actions artifacts expire after seven days; tagged public Releases use persistent downloadable attachments. This historical validation does not claim that every later development build is notarized.

References: [Apple notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [App Store Connect API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api), [GitHub signing setup](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).

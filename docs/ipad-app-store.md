# iPad App Store release

The iPad download is free. Creating and editing documents requires the monthly
`app.leftblank.writer.ipad.monthly` auto-renewable subscription. Eligible new
subscribers receive **two months free**, followed by **US $2.99/month** in the USA.
The app displays Apple's localized price and checks introductory-offer eligibility;
it never starts a local countdown or treats installing the app as a subscription.
Apple permits one introductory offer per subscription group. Mac remains free.
Expired subscriptions retain access to reading, PDF export and complete project
export, including source and assets.

## Storefront preparation

`iPad/Storefront/manifest.json` is the business configuration; `en-US.json` and
`zh-Hans.json` provide final localized storefront copy. The initial iPad version is
`1.0.0 (1)` in `iPad/Info.plist`, independently versioned from Mac. Subsequent iPad
releases must increase the build number; Apple preflight checks previous iOS builds.

In existing App Store Connect app **6818442294**, add the **iOS** platform with
bundle ID `app.leftblank.writer`. Keep the download price free. Create subscription
group **LeftBlank iPad**, then its monthly product using the exact ID above. Set
the USA base price to **$2.99** and use Apple's equalized local prices in available
territories. Add English and Simplified Chinese subscription/group localizations.
Configure a **Free Trial / 2 Months** introductory offer for every available
territory, with no end date if the offer should remain available to future users.
The offer's scheduling dates govern availability to new subscribers, not the
length of any subscriber's trial.

Add real iPad screenshots in Apple's required 13-inch screenshot slot, the
subscription's review screenshot, support and privacy URLs, age rating, export
compliance and review contact information. Mac screenshot assets cannot establish
iPad screenshots. The app contains no analytics or advertising SDK; subscriptions
are handled by StoreKit on the device. Check the App Privacy answers against the
final binary and policy before submission.

The current published privacy policy covers Mac. Before submitting iPad, publish
the bilingual additions prepared in `iPad/Storefront/privacy-additions.md` at
`https://leftblank.app/privacy.html`. This repository change prepares that text;
it does not publish the website or claim that production StoreKit products exist.
Accepting the Paid Applications Agreement, banking and tax setup requires the
account owner's App Store Connect configuration.

## Signed build

Create an **App Store iOS distribution** provisioning profile for the existing
App ID, production `iCloud.app.leftblank.writer` container and the Apple
Distribution certificate already used by CI. Add its base64 contents to repository
secret `IPAD_APPSTORE_PROVISIONING_PROFILE`. The workflow reuses
`APPSTORE_DISTRIBUTION_P12`, `APPSTORE_CERTIFICATE_PASSWORD`,
`APPSTORE_CONNECT_KEY_ID`, `APPSTORE_CONNECT_ISSUER_ID`,
`APPSTORE_CONNECT_PRIVATE_KEY` and variable `APP_STORE_APP_ID` from Mac releases.
It does not need the Mac installer certificate.

Validate the preparation without credentials:

```sh
source scripts/environment.sh
python3 scripts/test-ipad-release.py
python3 scripts/ipad_release.py
```

After merging and confirming the required Mac/iPad CI gate passed for the source
commit, tag that immutable main commit as `ipad-v1.0.0`. Dispatch **iPad App Store
build** on main with that tag. This workflow is separate from the Mac `v*`
release workflow. It checks the tag, source commit, store text, price/trial,
production profile, iCloud permissions, versions, device family and absent desktop
helpers; signs a native archive; exports the IPA; uploads it; and confirms Apple's
processing and App Store eligibility. It records iOS provenance in the tag's draft
GitHub Release before upload and refuses to reuse a manually uploaded build without
matching provenance. The exact IPA, source metadata and processing status are saved
as Actions artifacts. Retries reuse the same tag, source and build; never move a tag
or force-push.

This workflow uploads a build for review. It deliberately stops before the first
iOS submission because Apple's first subscription and its subscription group must
be reviewed together with a new app version. In App Store Connect, attach the
processed build to iPad `1.0.0`, add the app version, monthly subscription and group
to **the same draft submission**, verify the storefront and review screenshot,
and submit them together. Successful build processing is not App Review approval.

## Validation before review

Hosted CI measures executable iPad Swift/Core coverage and runs the native UI
suite, hosted unit/lifecycle tests, Address Sanitizer, Thread Sanitizer and Main
Thread Checker. Compiler concurrency checks and warnings are enforced. Rust FFI
formatting and Clippy checks supplement the embedded-engine integration test.
Xcode's Swift sanitizer instrumentation does not instrument the precompiled Rust
library. See `docs/coverage.md` for the coverage denominator and gate.

Test the StoreKit configuration in Xcode, then Apple's Sandbox/TestFlight product:
eligible two-month offer, ineligible returning subscriber, cancellation, pending
approval, verified renewal, expiration, restore, refunds/revocation, billing grace
and retry, and offline relaunch. Confirm expired users can export full source and
assets. StoreKit's local test configuration never travels inside an App Store app;
local purchases are not evidence that App Store Connect pricing is configured.
Also complete the real-device IME, accessibility, suspension and iCloud checks in
`docs/ipad.md`.

Apple references: [introductory offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions),
[first subscription review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/),
[screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

# iPad App Store screenshots

These are actual XCUITest attachments from the 13-inch iPad Air (M4) simulator,
running the app in English or Simplified Chinese. The public storefront uses the
locale-specific order in `../manifest.json`.

| Image | Language | Appearance | Screen |
| --- | --- | --- | --- |
| `01-preview.png` | English | Light | Rendered welcome document |
| `en-dark-writing.png` | English | Dark | Editor and live preview |
| `02-writing.png` | English | Light | Editing a document |
| `03-templates.png` | English | Dark | Template browser in portrait |
| `zh-light-preview.png` | Simplified Chinese | Light | Rendered welcome document |
| `zh-dark-preview.png` | Simplified Chinese | Dark | Rendered welcome document |
| `subscription.png` | English | Light | Subscription purchase and restore |

Landscape captures were losslessly oriented into 2732 × 2048 pixels; portrait
captures are 2048 × 2732. Only the orientation was normalized for Apple's 13-inch
screenshot slot. The interface and document contents were not retouched.

The dark template browser capture comes from the native full-screen presentation,
including portrait/landscape rotation and preserved search/selection checks.

The subscription review image uses the checked-in StoreKit test configuration.
Its two-week trial and USD 2.99 monthly price describe the confirmed business
model. Production pricing and offer eligibility still come from Apple, and the
release workflow separately configures and verifies those resources.

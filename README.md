# NightPdf

A PDF reader for iPhone, iPad, and Mac, made for reading in the dark.

- **Dark pages that keep their colors.** Pages invert their luminance but keep hues, so text turns light on a soft dark gray while a red line in a chart stays red.
- **Knock to scroll** (iPhone and iPad). Lay the device on a table and knock beside it: twice to scroll forward, three times to scroll back.
- **Search, contents, and page thumbnails**, with a Back button after following a link.
- **Vertical, page-by-page, or two-page layouts**, and it remembers where you left off.

No accounts, no tracking, no network access. See the [privacy policy](https://alundorzhu.github.io/NightPdf/privacy).

## Building

Open `NightPdf.xcodeproj` in Xcode 26 or later and run the `NightPdf` scheme. One target builds for iOS, iPadOS, and macOS.

## Tests

- Unit tests: the `UnitTests` test plan.
- UI tests: `scripts/run-ui-tests.sh`, which seeds the PDFs in `TestAssets/` into the simulator first.
- App Store screenshots: `scripts/take-screenshots.sh`.

## License

[MIT](LICENSE)

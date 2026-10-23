# NightPdf — App Store Connect listing

Copy each field into App Store Connect. Character limits are in brackets.

## App Information (left sidebar → App Information)

| Field | Value |
|---|---|
| Name [30] | NightPdf: Dark PDF Reader |
| Subtitle [30] | Read PDFs comfortably at night |
| Bundle ID | com.alundor.NightPdf |
| Primary category | Productivity |
| Secondary category | Books |
| Content rights | No, it does not contain, show, or access third-party content |
| Age rating | Answer "None" / "No" to every question → 4+ |

## Version page (iOS App 1.0, then the same for macOS App 1.0)

**Promotional text [170]**

> Dark pages that keep their colors, fast search, and a contents sidebar. On iPhone and iPad, knock on the table beside your device to scroll without touching it.

**Description [4000]**

> NightPdf is a PDF reader made for reading in the dark.
>
> Most dark modes leave the page bright, or invert it so figures turn strange colors. NightPdf darkens the page while keeping hues: text turns light on a soft dark gray, and a red line in a chart stays red. It's easier on your eyes, and the room around you stays dark.
>
> DARK PAGES THAT KEEP THEIR COLORS
> • Choose Dark, Light, or Match System for the pages, separately from the app's appearance
> • Charts, diagrams, and highlighted text keep their colors
> • Works with rotated and cropped pages
>
> KNOCK TO SCROLL (iPhone and iPad)
> • Lay your device on a table and knock twice beside it to scroll forward, three times to scroll back
> • Handy when you're eating, taking notes, or your hands are busy
> • Adjust the knock strength so it suits your table and how hard you knock
>
> FIND YOUR WAY AROUND
> • Search the whole document, step through matches, or see every result with its context
> • Jump through the table of contents or page thumbnails
> • Follow links inside a paper, then tap Back to return where you were
> • Picks up where you left off in each document
>
> READ YOUR WAY
> • Vertical scrolling, page by page, or two pages side by side
> • Opens PDFs from Files, iCloud Drive, and other apps, and reads them in place
> • On the Mac: a contents sidebar, menu commands, and keyboard shortcuts
>
> PRIVATE BY DESIGN
> NightPdf has no accounts, no ads, and no tracking. Your documents never leave your device.

**Keywords [100]**

```
night,viewer,papers,documents,ebook,knock,hands-free,scroll,study,eye strain,invert,textbook,lecture
```

| Field | Value |
|---|---|
| Support URL | https://alundorzhu.github.io/NightPdf/ |
| Marketing URL | leave empty |
| Copyright | 2026 Ziqiang Zhu |
| Version | 1.0 |

## Screenshots

Upload in this order (the first two appear in search results):

- **iPhone 6.9"**: `AppStore/screenshots/iPhone 17 Pro Max/` → 1-night, 2-figure, 3-contents, 4-search, 5-pages
- **iPad 13"**: `AppStore/screenshots/iPad Pro 13-inch (M5)/` → same order
- **Mac**: `AppStore/screenshots/Mac/` (2880×1800)

Regenerate the iPhone and iPad sets with `scripts/take-screenshots.sh`.

## App Privacy (left sidebar → App Privacy)

- Privacy Policy URL: https://alundorzhu.github.io/NightPdf/privacy
- "Do you or your third-party partners collect data from this app?" → **No, we do not collect data from this app**
- Result: **Data Not Collected**

## Pricing and Availability

- Price: Free (or pick a tier)
- Availability: all countries, or remove EU countries if you'd rather not declare trader status

## EU Digital Services Act (Business → Agreements, or prompted on first submission)

- If the app is free and you aren't running it as a business: **"I'm not a trader"**. Nothing is shown publicly.

## App Review Information

| Field | Value |
|---|---|
| Sign-in required | No |
| Contact | your name, phone, and email (only Apple sees these) |

**Notes**

> NightPdf is a PDF reader. To try it, open any PDF from the Files app, or from the document browser that appears when the app launches.
>
> Dark pages: tap the ••• (More) button → Page Color → Dark. Pages darken while figures keep their colors.
>
> Knock to Scroll (iPhone and iPad only): tap ••• → Knock to Scroll…, turn it on, and lay the device flat on a table. Knock on the table next to the device twice to scroll forward, three times to scroll back. The Try It buttons at the bottom of that screen show the same scrolling without knocking. It uses the accelerometer only while a document is open, needs no permission, and stores nothing.
>
> The app collects no data and makes no network requests.

## Export compliance

Already answered in the build (ITSAppUsesNonExemptEncryption = NO), so App Store Connect won't ask.

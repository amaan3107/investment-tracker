# Investment Tracker

A private iPhone app that combines all your investments into one place to track. Bring in holdings from **Wealthsimple**, **Questrade** or any other broker. You enter your own trades; the app pulls live prices and shows your book cost, average price, today's return and total return. Once installed, it appears on your home screen as **Portfolio**.

No account, no server, no bank logins. **Your trades are stored only on your iPhone.**

<p align="center">
  <img src="docs/screenshots/portfolio.png" width="260" alt="Portfolio screen with total value, today's return, total return and book cost, and a list of holdings (sample data)">
  &nbsp;&nbsp;
  <img src="docs/screenshots/portfolio-etfs.png" width="260" alt="Holdings list showing ETFs, each with its price and the time of that price (sample data)">
  &nbsp;&nbsp;
  <img src="docs/screenshots/portfolio-dark.png" width="260" alt="Portfolio screen in dark mode (sample data)">
</p>

> [!NOTE]
> **These aren't real investments.** Every screenshot uses made-up sample data from the app's built-in demo mode, not anyone's actual portfolio. Real data never leaves the phone it's entered on.

## Why
Each broker only shows its own accounts, and tools like Google Finance can't hold everything. This app puts every investment in one list, in CAD, without handing your data to anyone.

## Features
| | |
|---|---|
| **One portfolio** | Every account from every broker in one list, or filter to a broker or a single account (TFSA, RRSP, FHSA, non-registered) |
| **The numbers that matter** | Book cost, average price, market value, today's return and total return, per holding and for the whole portfolio |
| **Live prices** | Canadian (`.TO`) and US stocks and ETFs, plus USD → CAD, each shown with the time of the price |
| **USD holdings** | Shown in USD, converted to CAD in totals. Optionally record the CAD you actually paid so book cost matches your broker |
| **Sells** | Average-cost (ACB) method per account, the way Canadian brokers report it, with realized gains |
| **Your own price** | Override any price, such as a mutual fund's daily price or a price your broker shows |
| **Private** | Face ID lock, data stored only on the device, JSON backup and restore |

## Screens
*Sample data for illustration only.*

| Holding | Filter by account |
|---|---|
| <img src="docs/screenshots/holding.png" width="240" alt="Apple holding with quantity, average price, book cost, market value, returns and realized gains (sample data)"> | <img src="docs/screenshots/filter.png" width="240" alt="Account filter menu listing all accounts, each broker, and each individual account (sample data)"> |

| Activity | Settings |
|---|---|
| <img src="docs/screenshots/activity.png" width="240" alt="Activity list of buys and sells grouped by month (sample data)"> | <img src="docs/screenshots/settings.png" width="240" alt="Settings with Face ID lock, backup export and restore, and current prices (sample data)"> |

## How the numbers work
| Number | How it's worked out |
|---|---|
| **Book cost** | What you paid, including fees. When you sell, it goes down by the sold shares' share of the average cost |
| **Average price** | Book cost ÷ shares you still hold |
| **Market value** | Shares × latest price |
| **Today's return** | Shares held since yesterday × (price − yesterday's close), plus anything bought today × (price − your purchase price) |
| **Total return** | Market value − book cost (on what you still hold) |
| **Realized** | Money from sales − the average cost of the shares you sold |

Each account keeps its own average cost, like your broker does. USD holdings show in USD on their own page and convert to CAD in the totals.

### Prices
Prices come from Yahoo Finance's public quote service. Only **ticker symbols** are sent (for example `XEQT.TO`), never your quantities, costs or accounts. Prices refresh when you open the app or pull down to refresh.

| Type | Typical delay |
|---|---|
| US stocks and ETFs | Near real-time |
| Canadian stocks and ETFs (`.TO`) | ~15 minutes |
| Mutual-fund index funds | One price per day, after the close |

If a price can't be loaded, the app uses the last saved price, then your own price, then your last trade price.

## Using the app
1. **Add a trade:** tap **+**, pick the type of investment, then search a name or ticker (`XEQT`, `Apple`…). Canadian listings end in `.TO`.
2. **Fill in the details:** Buy or Sell, date, broker, account, shares, price and fees. *Total paid* is optional and is worked out for you.
3. **See a holding:** tap it for its numbers, a per-account breakdown, the price and its time, and every transaction.
4. **Edit or delete:** tap a transaction to edit it, or swipe left to delete it (also from the **Activity** tab).
5. **Filter:** use the button at the top left of **Portfolio** to show one broker or account.
6. **Back up:** **Settings → Export backup** saves a JSON file to Files or iCloud Drive. **Restore from backup** brings it back.

## Install on your iPhone
This isn't on the App Store. You build it onto your own phone with Xcode, which is free.

**You need:** a Mac with [Xcode](https://apps.apple.com/app/xcode/id497799835), an iPhone (iOS 17 or later), a USB cable and an Apple ID.

1. **Get the code:** click the green **Code** button above → **Download ZIP** and unzip it (or `git clone` it).
2. **Sign in to Xcode:** open **Xcode → Settings → Accounts**, click **+** and add your Apple ID. A free account works.
3. **Add your Team ID:**
   - In `Portfolio/Config/`, copy `Signing.local.xcconfig.example` to `Signing.local.xcconfig`.
   - Replace `YOUR_TEAM_ID` with your Team ID. You'll find it in Xcode → Settings → Accounts → your Apple ID → Team.
   - This file is git-ignored, so your Team ID is never committed.
4. **Open the project:** double-click `Portfolio/Portfolio.xcodeproj`.
5. **Give the app your own ID:** click the blue **Portfolio** project → target **Portfolio** → **Signing & Capabilities**, and change the bundle identifier `com.private.portfoliotracker.k7q2` to something unique, e.g. `com.yourname.portfolio`.
6. **Connect your iPhone:** plug it in, unlock it and tap **Trust**. Then on the phone, turn on **Settings → Privacy & Security → Developer Mode** and restart when asked.
7. **Run:** pick your iPhone from the device menu at the top of Xcode and press **▶ Run** (⌘R). Keep the phone unlocked while it installs.
8. **Trust the app (first time only):** on the phone, go to **Settings → General → VPN & Device Management** → your Apple ID → **Trust**. Then open **Portfolio**.

> **Free Apple ID:** the app runs for 7 days, then stops opening. Plug the phone in and press **▶ Run** again; your data is kept. A paid Apple Developer account ($99 USD/year) extends this to a year.

### Try it with demo data
To see the app filled in (in the simulator or on a phone):
1. In Xcode, open **Product → Scheme → Edit Scheme… → Run → Arguments**.
2. Add `-demo` under *Arguments Passed On Launch*, then run.

This **replaces everything in the app** with a sample portfolio, so only use it on a simulator or a phone without real data. Remove the argument afterwards. Demo mode only exists in Debug builds.

## Project structure
| Path | What it is |
|---|---|
| `Portfolio/Portfolio/Models.swift` | Stored data: holdings and trades (SwiftData) |
| `Portfolio/Portfolio/Calculations.swift` | Book cost, averages, today's and total return, realized gains |
| `Portfolio/Portfolio/PriceService.swift` | Live prices, USD → CAD, ticker search |
| `Portfolio/Portfolio/Views/` | Screens: Portfolio, holding detail, add/edit trade, Activity, Settings |
| `Portfolio/Portfolio/Backup.swift` | JSON export and restore |
| `Portfolio/Portfolio/DemoData.swift` | Sample portfolio for `-demo` (Debug builds only) |
| `Portfolio/Config/` | Signing settings; your Team ID goes in the git-ignored `Signing.local.xcconfig` |

Built with SwiftUI and SwiftData, iOS 17+. No third-party dependencies.

## Notes
- Yahoo Finance's quote service is unofficial and could change without notice. If prices stop loading, the app keeps working with your own prices.
- This is a personal tracking tool, not financial or tax advice. Check your broker's statements for official figures.

## License
MIT — see [LICENSE](LICENSE).

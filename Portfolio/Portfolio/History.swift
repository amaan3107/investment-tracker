import Foundation

/// Calendar days as yyyymmdd integers, so prices from different exchanges line up by date.
enum DayKey {
    static func day(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// Midday on that day, in the phone's time zone (used for drawing the chart).
    static func date(_ day: Int) -> Date {
        let c = DateComponents(year: day / 10_000, month: day / 100 % 100, day: day % 100, hour: 12)
        return Calendar.current.date(from: c) ?? Date()
    }

    /// A market timestamp converted to the exchange's own calendar day.
    static func fromTimestamp(_ timestamp: Double, gmtOffset: Int) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return day(Date(timeIntervalSince1970: timestamp + Double(gmtOffset)), calendar: utc)
    }

    static func adding(days: Int, to day: Int) -> Int {
        Self.day(Calendar.current.date(byAdding: .day, value: days, to: date(day)) ?? date(day))
    }
}

/// Daily closing prices for one symbol.
struct DailySeries: Codable, Sendable {
    var days: [Int]        // sorted
    var closes: [Double]
    var fetchedAt: Date
    var fromDay: Int

    /// Close on `day`, or the latest close before it (weekends and holidays carry forward).
    func close(onOrBefore day: Int) -> Double? {
        var lo = 0, hi = days.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if days[mid] <= day { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found.map { closes[$0] }
    }
}

/// One point on the portfolio chart, in CAD.
struct HistoryPoint: Identifiable, Equatable {
    var day: Int
    var value: Double      // what your holdings were worth
    var invested: Double   // book cost: money you had put in (minus the cost of anything sold)
    var realized: Double = 0   // gains and losses locked in by sales up to this day
    var id: Int { day }
    var date: Date { DayKey.date(day) }
    /// Gain on what you still hold.
    var gain: Double { value - invested }
    /// Everything you've made or lost so far, including sales. Selling doesn't change this.
    var totalGain: Double { gain + realized }
}

enum PortfolioHistory {
    /// Replays your trades day by day and values what you held at each day's closing price.
    /// The last point is "now" and equals the live totals at the top of the screen.
    ///
    /// - Parameters:
    ///   - historyDays: the days a symbol has closing prices for.
    ///   - close: closing price for a symbol on or before a day (USD for US listings and gold futures).
    ///   - fxOnDay: USD → CAD on or before a day. USD costs without a CAD amount you entered are
    ///     converted at each day's rate (like Google Finance), so the gain matches the stock's move.
    static func build(assets: [Asset], filter: AccountFilter, currentFX: Double, today: Int,
                      now: (value: Double, invested: Double, realized: Double),
                      historyDays: (String) -> [Int],
                      close: (String, Int) -> Double?,
                      fxOnDay: (Int) -> Double?) -> [HistoryPoint] {
        /// `knownCAD`: CAD amount you entered (or the cash itself for CAD stocks); nil = convert at that day's rate.
        struct Row { var day: Int; var trade: Trade; var knownCAD: Double? }
        struct Item { var asset: Asset; var rows: [Row] }

        var items: [Item] = []
        for asset in assets {
            let trades = asset.trades.filter { filter.includes($0.account) }
            guard !trades.isEmpty else { continue }
            var rows: [Row] = []
            for t in trades {
                let known: Double? = asset.currency == .cad ? t.cashAmount : t.cadAmount
                rows.append(Row(day: DayKey.day(t.date), trade: t, knownCAD: known))
            }
            rows.sort { a, b in
                if a.day != b.day { return a.day < b.day }
                return a.trade.side == .buy && b.trade.side == .sell
            }
            items.append(Item(asset: asset, rows: rows))
        }
        guard let firstDay = items.compactMap({ $0.rows.first?.day }).min() else { return [] }

        // Every trading day (from any holding) since the first trade, plus trade days, up to yesterday.
        var daySet = Set<Int>()
        for item in items {
            for r in item.rows where r.day < today { daySet.insert(r.day) }
            let symbol = item.asset.isGold ? PriceService.goldFuturesSymbol : item.asset.symbol
            for d in historyDays(symbol) where d >= firstDay && d < today { daySet.insert(d) }
        }

        // Running per-account quantity and book cost for each holding
        // (cost in CAD where known, plus cost in the stock's currency still to be converted).
        var held = items.map { _ in [AccountRef: Holding]() }
        var nextRow = items.map { _ in 0 }
        var lastTradePrice = items.map { _ in Double?.none }
        var realized = 0.0
        var points: [HistoryPoint] = []

        for day in daySet.sorted() {
            let fx = fxOnDay(day) ?? currentFX
            var value = 0.0, invested = 0.0
            for i in items.indices {
                let item = items[i]
                while nextRow[i] < item.rows.count, item.rows[nextRow[i]].day <= day {
                    let row = item.rows[nextRow[i]]
                    realized += apply(row.trade, knownCAD: row.knownCAD, fx: fx, to: &held[i])
                    lastTradePrice[i] = row.trade.price
                    nextRow[i] += 1
                }
                let qty = held[i].values.reduce(0) { $0 + $1.qty }
                invested += held[i].values.reduce(0) { $0 + $1.knownCAD + $1.native * fx }
                guard qty > 1e-9 else { continue }
                if item.asset.isGold {
                    let cadPrice = close(PriceService.goldFuturesSymbol, day).map { $0 * fx } ?? lastTradePrice[i] ?? 0
                    value += qty * cadPrice
                } else {
                    let price = close(item.asset.symbol, day) ?? lastTradePrice[i] ?? 0
                    value += qty * price * (item.asset.currency == .usd ? fx : 1)
                }
            }
            points.append(HistoryPoint(day: day, value: value, invested: invested, realized: realized))
        }
        points.append(HistoryPoint(day: today, value: now.value, invested: now.invested, realized: now.realized))
        return points
    }

    private struct Holding {
        var qty = 0.0
        var knownCAD = 0.0   // cost already in CAD
        var native = 0.0     // USD cost to convert at the day's rate
    }

    /// Same average-cost rules as `Position.build`. Returns the realized gain in CAD (sells only).
    private static func apply(_ t: Trade, knownCAD: Double?, fx: Double,
                              to held: inout [AccountRef: Holding]) -> Double {
        var e = held[t.account] ?? Holding()
        var realized = 0.0
        switch t.side {
        case .buy:
            e.qty += t.quantity
            if let knownCAD { e.knownCAD += knownCAD } else { e.native += t.cashAmount }
        case .sell:
            guard e.qty > 0, t.quantity > 0 else { return 0 }
            let sold = min(t.quantity, e.qty)
            let share = sold / e.qty
            let costOutCAD = (e.knownCAD + e.native * fx) * share
            let proceedsCAD = knownCAD ?? t.cashAmount * fx
            realized = proceedsCAD * (sold / t.quantity) - costOutCAD
            e.knownCAD -= e.knownCAD * share
            e.native -= e.native * share
            e.qty -= sold
            if e.qty < 1e-9 { e = Holding() }
        }
        held[t.account] = e
        return realized
    }
}

/// Chart time ranges, like Google Finance.
enum ChartRange: String, CaseIterable, Identifiable {
    case week = "1W", month = "1M", threeMonths = "3M", ytd = "YTD", year = "1Y", all = "All"
    var id: String { rawValue }

    /// First day shown, or nil for everything.
    func startDay(today: Int) -> Int? {
        switch self {
        case .week: DayKey.adding(days: -7, to: today)
        case .month: DayKey.day(Calendar.current.date(byAdding: .month, value: -1, to: DayKey.date(today))!)
        case .threeMonths: DayKey.day(Calendar.current.date(byAdding: .month, value: -3, to: DayKey.date(today))!)
        case .ytd: (today / 10_000) * 10_000 + 101
        case .year: DayKey.day(Calendar.current.date(byAdding: .year, value: -1, to: DayKey.date(today))!)
        case .all: nil
        }
    }

    var caption: String {
        switch self {
        case .week: "past week"
        case .month: "past month"
        case .threeMonths: "past 3 months"
        case .ytd: "this year"
        case .year: "past year"
        case .all: "all time"
        }
    }

    /// Points in range, starting from the last point before the range so the change has a baseline.
    func slice(_ points: [HistoryPoint], today: Int) -> [HistoryPoint] {
        guard let start = startDay(today: today) else { return points }
        guard let firstIn = points.firstIndex(where: { $0.day >= start }) else { return Array(points.suffix(1)) }
        // Use the close on the start day if there is one, else the last close before it.
        let from = points[firstIn].day == start ? firstIn : max(0, firstIn - 1)
        return Array(points[from...])
    }
}

import Foundation

/// The price used to value a holding right now.
struct PriceInfo {
    enum Source { case live, manual, lastTrade }
    var price: Double
    var previousClose: Double
    var source: Source
    var asOf: Date?
}

/// Which accounts to include.
enum AccountFilter: Hashable {
    case all
    case broker(Broker)
    case account(AccountRef)

    func includes(_ account: AccountRef) -> Bool {
        switch self {
        case .all: true
        case .broker(let b): account.broker == b
        case .account(let a): account == a
        }
    }

    var label: String {
        switch self {
        case .all: "All accounts"
        case .broker(let b): b.label
        case .account(let a): a.label
        }
    }
}

/// A holding of one asset, worked out from its trades using the average-cost (ACB) method.
/// Amounts are in the asset's own currency unless the name ends in `CAD`.
struct Position: Identifiable {
    let asset: Asset
    var accounts: Set<AccountRef> = []
    var id: String { asset.symbol }

    /// CAD per one unit of the asset's currency (1 for CAD assets).
    var fx: Double = 1
    var priceInfo: PriceInfo?

    var quantity = 0.0
    var bookCost = 0.0
    var bookCostCAD = 0.0
    var realized = 0.0
    var realizedCAD = 0.0
    var feesPaid = 0.0

    // Totals over every buy (used for the gold averages).
    var totalInvested = 0.0
    var totalAfterFees = 0.0
    var quantityBought = 0.0
    var priceTimesQuantity = 0.0

    // Buys made today (so today's return uses your purchase price, not yesterday's close).
    var quantityBoughtToday = 0.0
    var valueBoughtToday = 0.0

    var tradeCount = 0

    // MARK: Building

    /// Builds the position for one account. ACB is tracked per account, as brokers do.
    /// `tradeFX` gives USD → CAD on a trade's date, for USD trades without a CAD amount
    /// (falls back to today's rate `fx`).
    static func build(asset: Asset, trades: [Trade], fx: Double, priceInfo: PriceInfo?,
                      tradeFX: ((Date) -> Double?)? = nil) -> Position {
        var p = Position(asset: asset)
        p.fx = fx
        p.priceInfo = priceInfo
        // Same order as the chart: by calendar day, buys before sells on the same day.
        let sorted = trades.sorted {
            let a = DayKey.day($0.date), b = DayKey.day($1.date)
            if a != b { return a < b }
            return $0.side == .buy && $1.side == .sell
        }
        let isCAD = asset.currency == .cad
        for t in sorted {
            p.accounts.insert(t.account)
            p.tradeCount += 1
            p.feesPaid += t.fees
            let cash = t.cashAmount
            let cashCAD = isCAD ? cash : (t.cadAmount ?? cash * (tradeFX?(t.date) ?? fx))
            switch t.side {
            case .buy:
                p.quantity += t.quantity
                p.bookCost += cash
                p.bookCostCAD += cashCAD
                p.totalInvested += cash
                p.totalAfterFees += t.amountAfterFees ?? (t.quantity * t.price)
                p.quantityBought += t.quantity
                p.priceTimesQuantity += t.quantity * t.price
                if Calendar.current.isDateInToday(t.date) {
                    p.quantityBoughtToday += t.quantity
                    p.valueBoughtToday += t.quantity * t.price
                }
            case .sell:
                guard p.quantity > 0, t.quantity > 0 else { continue }
                let q = min(t.quantity, p.quantity)
                let share = q / t.quantity          // portion of this sale we can match
                let ratio = q / p.quantity          // portion of the holding sold
                let costOut = p.bookCost * ratio
                let costOutCAD = p.bookCostCAD * ratio
                p.realized += cash * share - costOut
                p.realizedCAD += cashCAD * share - costOutCAD
                p.bookCost -= costOut
                p.bookCostCAD -= costOutCAD
                p.quantity -= q
                if p.quantity < 1e-9 {
                    p.quantity = 0; p.bookCost = 0; p.bookCostCAD = 0
                }
            }
        }
        return p
    }

    /// Adds another account's position of the same asset.
    mutating func merge(_ o: Position) {
        accounts.formUnion(o.accounts)
        quantity += o.quantity
        bookCost += o.bookCost
        bookCostCAD += o.bookCostCAD
        realized += o.realized
        realizedCAD += o.realizedCAD
        feesPaid += o.feesPaid
        totalInvested += o.totalInvested
        totalAfterFees += o.totalAfterFees
        quantityBought += o.quantityBought
        priceTimesQuantity += o.priceTimesQuantity
        quantityBoughtToday += o.quantityBoughtToday
        valueBoughtToday += o.valueBoughtToday
        tradeCount += o.tradeCount
    }

    // MARK: Results

    var isOpen: Bool { quantity > 1e-9 }

    /// Book cost ÷ quantity (includes fees).
    var averagePrice: Double? { isOpen ? bookCost / quantity : nil }

    /// Gold: total invested ÷ total ounces bought (includes fees).
    var averageCostPerUnitAllBuys: Double? { quantityBought > 0 ? totalInvested / quantityBought : nil }
    /// Gold: average of the prices you bought at, weighted by ounces.
    var averagePurchasePrice: Double? { quantityBought > 0 ? priceTimesQuantity / quantityBought : nil }
    var totalFeesOnBuys: Double { max(0, totalInvested - totalAfterFees) }

    var price: Double? { priceInfo?.price }

    var marketValue: Double? { price.map { quantity * $0 } }
    var marketValueCAD: Double? { marketValue.map { $0 * fx } }

    private var heldSinceYesterday: Double { max(0, quantity - min(quantityBoughtToday, quantity)) }
    private var todayQuantity: Double { min(quantityBoughtToday, quantity) }
    private var averageTodayPrice: Double { quantityBoughtToday > 0 ? valueBoughtToday / quantityBoughtToday : 0 }

    var todayReturn: Double? {
        guard isOpen, let info = priceInfo else { return nil }
        return heldSinceYesterday * (info.price - info.previousClose)
            + todayQuantity * (info.price - averageTodayPrice)
    }

    var todayReturnCAD: Double? { todayReturn.map { $0 * fx } }

    /// Value at the start of the day (yesterday's close, or today's purchase price).
    var todayStartValue: Double? {
        guard isOpen, let info = priceInfo else { return nil }
        return heldSinceYesterday * info.previousClose + todayQuantity * averageTodayPrice
    }

    var todayReturnPercent: Double? {
        guard let r = todayReturn, let start = todayStartValue, start > 0 else { return nil }
        return r / start
    }

    /// Unrealized return on what you still hold, in the asset's currency.
    var totalReturn: Double? { marketValue.map { $0 - bookCost } }
    var totalReturnPercent: Double? {
        guard let r = totalReturn, bookCost > 0 else { return nil }
        return r / bookCost
    }

    /// Unrealized return in CAD (includes currency moves for USD holdings).
    var totalReturnCAD: Double? { marketValueCAD.map { $0 - bookCostCAD } }
    var totalReturnCADPercent: Double? {
        guard let r = totalReturnCAD, bookCostCAD > 0 else { return nil }
        return r / bookCostCAD
    }
}

/// Portfolio-wide totals in CAD.
struct PortfolioSummary {
    var marketValue = 0.0
    var bookCost = 0.0
    var todayReturn = 0.0
    var todayStartValue = 0.0
    var realized = 0.0

    var totalReturn: Double { marketValue - bookCost }
    var totalReturnPercent: Double? { bookCost > 0 ? totalReturn / bookCost : nil }
    var todayReturnPercent: Double? { todayStartValue > 0 ? todayReturn / todayStartValue : nil }

    init(positions: [Position]) {
        for p in positions {
            realized += p.realizedCAD
            guard p.isOpen else { continue }
            marketValue += p.marketValueCAD ?? p.bookCostCAD
            bookCost += p.bookCostCAD
            todayReturn += p.todayReturnCAD ?? 0
            todayStartValue += (p.todayStartValue ?? 0) * p.fx
        }
    }
}

enum PortfolioBuilder {
    /// One position per asset (accounts merged), limited to the accounts in `filter`.
    static func positions(assets: [Asset], filter: AccountFilter, fx: Double,
                          tradeFX: ((Date) -> Double?)? = nil,
                          priceFor: (Asset, [Trade]) -> PriceInfo?) -> [Position] {
        var result: [Position] = []
        for asset in assets {
            let trades = asset.trades.filter { filter.includes($0.account) }
            guard !trades.isEmpty else { continue }
            result.append(position(asset: asset, trades: trades, fx: fx, priceInfo: priceFor(asset, trades),
                                   tradeFX: tradeFX))
        }
        return result
    }

    static func position(asset: Asset, trades: [Trade], fx: Double, priceInfo: PriceInfo?,
                         tradeFX: ((Date) -> Double?)? = nil) -> Position {
        let rate = asset.currency == .cad ? 1 : fx
        let byAccount = Dictionary(grouping: trades, by: { $0.account })
        var merged: Position?
        for (_, accountTrades) in byAccount.sorted(by: { $0.key.id < $1.key.id }) {
            let p = Position.build(asset: asset, trades: accountTrades, fx: rate, priceInfo: priceInfo,
                                   tradeFX: tradeFX)
            if merged == nil { merged = p } else { merged!.merge(p) }
        }
        return merged ?? Position(asset: asset, fx: rate, priceInfo: priceInfo)
    }
}

/// One row of a holding's transaction table (like Google Finance's purchase lots).
/// Buys show what's still held from that purchase; sells show the sale and its realized gain.
/// Sales shrink every open purchase in that account proportionally (the average-cost method),
/// so the rows add up to the holding's totals. Amounts are kept in the stock's own currency
/// and in CAD (cost converted at the purchase-day rate, like your broker).
struct LotRow: Identifiable {
    let trade: Trade
    var remainingQuantity: Double   // buy: still held from this purchase · sell: quantity sold
    var remainingCost = 0.0         // buy: cost of what's still held (stock's currency)
    var remainingCostCAD = 0.0
    var realized: Double?           // sell: gain or loss on the sale (stock's currency)
    var realizedCAD: Double?
    var proceedsCAD = 0.0           // sell: money received, in CAD
    var id: ObjectIdentifier { ObjectIdentifier(trade) }
    var isSell: Bool { trade.side == .sell }

    /// - Parameter fx: CAD per unit of the stock's currency today (1 for CAD stocks).
    func marketValue(_ info: PriceInfo?, inCAD: Bool, fx: Double) -> Double? {
        if isSell { return inCAD ? proceedsCAD : trade.cashAmount }
        return info.map { remainingQuantity * $0.price * (inCAD ? fx : 1) }
    }

    func totalGain(_ info: PriceInfo?, inCAD: Bool, fx: Double) -> Double? {
        if isSell { return inCAD ? realizedCAD : realized }
        return marketValue(info, inCAD: inCAD, fx: fx).map { $0 - (inCAD ? remainingCostCAD : remainingCost) }
    }

    func totalGainPercent(_ info: PriceInfo?, inCAD: Bool, fx: Double) -> Double? {
        guard let g = totalGain(info, inCAD: inCAD, fx: fx) else { return nil }
        let base: Double
        if isSell {
            base = (inCAD ? proceedsCAD : trade.cashAmount) - (inCAD ? (realizedCAD ?? 0) : (realized ?? 0))
        } else {
            base = inCAD ? remainingCostCAD : remainingCost
        }
        return base > 0 ? g / base : nil
    }
}

enum LotBuilder {
    /// Rows in date order (oldest first).
    /// - Parameters:
    ///   - currentFX: today's CAD per unit of the stock's currency (1 for CAD stocks).
    ///   - tradeFX: the rate on a trade's date, when known.
    static func rows(trades: [Trade], isCAD: Bool = true, currentFX: Double = 1,
                     tradeFX: ((Date) -> Double?)? = nil) -> [LotRow] {
        func cad(_ t: Trade) -> Double {
            if isCAD { return t.cashAmount }
            return t.cadAmount ?? t.cashAmount * (tradeFX?(t.date) ?? currentFX)
        }
        let sorted = trades.sorted {
            let a = DayKey.day($0.date), b = DayKey.day($1.date)
            if a != b { return a < b }
            return $0.side == .buy && $1.side == .sell
        }
        var rows: [LotRow] = []
        var openByAccount: [AccountRef: [Int]] = [:]   // indexes into `rows`
        for t in sorted {
            switch t.side {
            case .buy:
                openByAccount[t.account, default: []].append(rows.count)
                rows.append(LotRow(trade: t, remainingQuantity: t.quantity,
                                   remainingCost: t.cashAmount, remainingCostCAD: cad(t)))
            case .sell:
                let open = openByAccount[t.account] ?? []
                let held = open.reduce(0) { $0 + rows[$1].remainingQuantity }
                var realized = 0.0, realizedCAD = 0.0
                let proceedsCAD = cad(t)
                if held > 0, t.quantity > 0 {
                    let sold = min(t.quantity, held)
                    let keep = 1 - sold / held
                    var costOut = 0.0, costOutCAD = 0.0
                    for i in open {
                        costOut += rows[i].remainingCost * (1 - keep)
                        costOutCAD += rows[i].remainingCostCAD * (1 - keep)
                        rows[i].remainingQuantity *= keep
                        rows[i].remainingCost *= keep
                        rows[i].remainingCostCAD *= keep
                        if rows[i].remainingQuantity < 1e-9 {
                            rows[i].remainingQuantity = 0; rows[i].remainingCost = 0; rows[i].remainingCostCAD = 0
                        }
                    }
                    realized = t.cashAmount * (sold / t.quantity) - costOut
                    realizedCAD = proceedsCAD * (sold / t.quantity) - costOutCAD
                }
                rows.append(LotRow(trade: t, remainingQuantity: t.quantity, realized: realized,
                                   realizedCAD: realizedCAD, proceedsCAD: proceedsCAD))
            }
        }
        return rows
    }
}

#if DEBUG
import Foundation
import SwiftData

/// Made-up sample trades for trying the app and taking screenshots.
/// Only in Debug builds. Launch with the `-demo` argument
/// (Xcode → Product → Scheme → Edit Scheme → Run → Arguments) to replace
/// everything in the app with this sample portfolio.
enum DemoData {
    static var isRequested: Bool { CommandLine.arguments.contains("-demo") }

    static func load(into context: ModelContext) {
        try? context.delete(model: Trade.self)
        try? context.delete(model: Asset.self)

        let wsTFSA = AccountRef(broker: .wealthsimple, type: .tfsa)
        let qtTFSA = AccountRef(broker: .questrade, type: .tfsa)
        let qtRRSP = AccountRef(broker: .questrade, type: .rrsp)

        func daysAgo(_ d: Int) -> Date { Calendar.current.date(byAdding: .day, value: -d, to: .now)! }

        func asset(_ symbol: String, _ name: String, _ kind: AssetKind, _ currency: Currency) -> Asset {
            let a = Asset(symbol: symbol, name: name, kind: kind, currency: currency)
            context.insert(a)
            return a
        }

        func add(_ a: Asset, _ t: Trade) {
            context.insert(t)
            t.asset = a
        }

        let xeqt = asset("XEQT.TO", "iShares Core Equity ETF Portfolio", .etf, .cad)
        add(xeqt, Trade(side: .buy, account: wsTFSA, date: daysAgo(210), quantity: 120, price: 38.50))
        add(xeqt, Trade(side: .buy, account: wsTFSA, date: daysAgo(62), quantity: 60, price: 41.20))

        let vfv = asset("VFV.TO", "Vanguard S&P 500 Index ETF", .etf, .cad)
        add(vfv, Trade(side: .buy, account: qtRRSP, date: daysAgo(300), quantity: 25, price: 142.10, fees: 4.95))

        let shop = asset("SHOP.TO", "Shopify Inc.", .stock, .cad)
        add(shop, Trade(side: .buy, account: wsTFSA, date: daysAgo(150), quantity: 15, price: 150.00))

        let aapl = asset("AAPL", "Apple Inc.", .stock, .usd)
        add(aapl, Trade(side: .buy, account: qtTFSA, date: daysAgo(250), quantity: 10, price: 245.00,
                        fees: 4.95, cadAmount: 3_420.00))
        add(aapl, Trade(side: .sell, account: qtTFSA, date: daysAgo(20), quantity: 3, price: 330.00,
                        fees: 4.95, cadAmount: 1_410.00))

        let gold = asset(Asset.goldSymbol, "Physical Gold", .gold, .cad)
        add(gold, Trade(side: .buy, account: wsTFSA, date: daysAgo(120), quantity: 0.211828, price: 4_650.00,
                        fees: 15.00, totalAmount: 1_000.00, amountAfterFees: 985.00))
        add(gold, Trade(side: .buy, account: wsTFSA, date: daysAgo(30), quantity: 0.097525, price: 5_050.00,
                        fees: 7.50, totalAmount: 500.00, amountAfterFees: 492.50))

        try? context.save()
    }
}
#endif

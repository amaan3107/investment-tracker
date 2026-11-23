import Foundation
import SwiftData

// MARK: - Enums

enum AssetKind: String, Codable, CaseIterable, Identifiable {
    case stock, etf, indexFund, gold

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stock: "Stock"
        case .etf: "ETF"
        case .indexFund: "Index Fund"
        case .gold: "Gold"
        }
    }

    var sectionTitle: String {
        switch self {
        case .stock: "Stocks"
        case .etf: "ETFs"
        case .indexFund: "Index Funds"
        case .gold: "Physical Gold"
        }
    }

    /// Unit used for quantities.
    var unitLabel: String { self == .gold ? "oz" : "shares" }
}

enum Broker: String, Codable, CaseIterable, Identifiable {
    case wealthsimple, questrade
    var id: String { rawValue }
    var label: String {
        switch self {
        case .wealthsimple: "Wealthsimple"
        case .questrade: "Questrade"
        }
    }
}

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case tfsa, rrsp, fhsa, nonRegistered
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tfsa: "TFSA"
        case .rrsp: "RRSP"
        case .fhsa: "FHSA"
        case .nonRegistered: "Non-registered"
        }
    }
}

enum TradeSide: String, Codable, CaseIterable, Identifiable {
    case buy, sell
    var id: String { rawValue }
    var label: String { self == .buy ? "Buy" : "Sell" }
}

enum Currency: String, Codable, CaseIterable, Identifiable {
    case cad = "CAD", usd = "USD"
    var id: String { rawValue }

    /// Best guess from a Yahoo symbol: Canadian exchanges use a suffix.
    static func guess(for symbol: String) -> Currency {
        let s = symbol.uppercased()
        for suffix in [".TO", ".V", ".NE", ".CN"] where s.hasSuffix(suffix) { return .cad }
        if s.hasPrefix("0P") { return .cad } // Yahoo ids for Canadian mutual funds
        return .usd
    }
}

/// Where a trade lives.
struct AccountRef: Hashable, Identifiable {
    var broker: Broker
    var type: AccountType
    var id: String { broker.rawValue + "-" + type.rawValue }
    var label: String { "\(broker.label) \(type.label)" }
}

// MARK: - Stored models

@Model
final class Asset {
    /// Yahoo Finance symbol (e.g. XEQT.TO, AAPL). Gold uses `Asset.goldSymbol`.
    var symbol: String
    var name: String
    var kindRaw: String
    var currencyRaw: String
    /// A price you typed yourself (used when `useManualPrice` is on, or when no live price exists).
    var manualPrice: Double?
    var useManualPrice: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Trade.asset)
    var trades: [Trade] = []

    static let goldSymbol = "GOLD-OZ"

    init(symbol: String, name: String, kind: AssetKind, currency: Currency) {
        self.symbol = symbol
        self.name = name
        self.kindRaw = kind.rawValue
        self.currencyRaw = currency.rawValue
    }

    var kind: AssetKind {
        get { AssetKind(rawValue: kindRaw) ?? .stock }
        set { kindRaw = newValue.rawValue }
    }

    var currency: Currency {
        get { Currency(rawValue: currencyRaw) ?? .cad }
        set { currencyRaw = newValue.rawValue }
    }

    var isGold: Bool { kind == .gold }

    var displaySymbol: String { isGold ? "GOLD" : symbol }
}

@Model
final class Trade {
    var uuid: UUID = UUID()
    var asset: Asset?
    var sideRaw: String
    var brokerRaw: String
    var accountRaw: String
    var date: Date
    /// Shares, or troy ounces for gold.
    var quantity: Double
    /// Price per share / per oz, in the asset's currency.
    var price: Double
    /// Fees in the asset's currency.
    var fees: Double = 0
    /// Total cash that left (buy) or arrived (sell), in the asset's currency.
    /// When nil it is worked out from quantity × price ± fees.
    var totalAmount: Double?
    /// Gold: the amount actually converted into gold after Wealthsimple's fee.
    var amountAfterFees: Double?
    /// USD assets: the CAD you actually paid or received (makes CAD book cost match your broker).
    var cadAmount: Double?
    var note: String = ""

    init(side: TradeSide, account: AccountRef, date: Date, quantity: Double, price: Double,
         fees: Double = 0, totalAmount: Double? = nil, amountAfterFees: Double? = nil,
         cadAmount: Double? = nil, note: String = "") {
        self.sideRaw = side.rawValue
        self.brokerRaw = account.broker.rawValue
        self.accountRaw = account.type.rawValue
        self.date = date
        self.quantity = quantity
        self.price = price
        self.fees = fees
        self.totalAmount = totalAmount
        self.amountAfterFees = amountAfterFees
        self.cadAmount = cadAmount
        self.note = note
    }

    var side: TradeSide {
        get { TradeSide(rawValue: sideRaw) ?? .buy }
        set { sideRaw = newValue.rawValue }
    }

    var account: AccountRef {
        get { AccountRef(broker: Broker(rawValue: brokerRaw) ?? .wealthsimple,
                         type: AccountType(rawValue: accountRaw) ?? .tfsa) }
        set { brokerRaw = newValue.broker.rawValue; accountRaw = newValue.type.rawValue }
    }

    /// Cash paid (buy, includes fees) or received (sell, after fees), in the asset's currency.
    var cashAmount: Double {
        if let totalAmount { return totalAmount }
        let gross = quantity * price
        return side == .buy ? gross + fees : gross - fees
    }
}

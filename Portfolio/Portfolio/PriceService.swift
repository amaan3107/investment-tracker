import Foundation
import Observation

/// A market quote. Only ticker symbols are ever sent over the network — never your holdings.
struct Quote: Codable, Sendable {
    var symbol: String
    var price: Double
    var previousClose: Double
    var currency: String
    var name: String?
    var marketTime: Date?
}

struct SymbolSearchResult: Identifiable, Hashable, Sendable {
    var symbol: String
    var name: String
    var exchange: String
    var quoteType: String
    var id: String { symbol }

    var suggestedKind: AssetKind {
        switch quoteType.uppercased() {
        case "ETF": .etf
        case "MUTUALFUND": .indexFund
        default: .stock
        }
    }
}

@MainActor
@Observable
final class PriceService {
    static let goldFuturesSymbol = "GC=F"      // gold, USD per troy ounce
    static let usdCadSymbol = "USDCAD=X"

    private(set) var quotes: [String: Quote] = [:]
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    private let cacheKey = "priceCache.v1"
    private let cacheDateKey = "priceCache.updated"

    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([String: Quote].self, from: data) {
            quotes = cached
        }
        lastUpdated = UserDefaults.standard.object(forKey: cacheDateKey) as? Date
    }

    /// CAD per 1 USD.
    var usdToCad: Double { quotes[Self.usdCadSymbol]?.price ?? 1.40 }
    var hasLiveFX: Bool { quotes[Self.usdCadSymbol] != nil }

    /// Live gold price in CAD per troy ounce (gold futures × USD/CAD).
    var goldQuoteCAD: Quote? {
        guard let g = quotes[Self.goldFuturesSymbol], let fx = quotes[Self.usdCadSymbol] else { return nil }
        return Quote(symbol: Asset.goldSymbol,
                     price: g.price * fx.price,
                     previousClose: g.previousClose * fx.previousClose,
                     currency: "CAD", name: "Gold (CAD / troy oz)",
                     marketTime: g.marketTime)
    }

    func liveQuote(for asset: Asset) -> Quote? {
        asset.isGold ? goldQuoteCAD : quotes[asset.symbol]
    }

    /// Picks the price to value a holding: your manual price if switched on, else live,
    /// else your manual price, else the last price you traded at.
    func priceInfo(for asset: Asset, trades: [Trade]) -> PriceInfo? {
        let live = liveQuote(for: asset)
        if asset.useManualPrice, let manual = asset.manualPrice, manual > 0 {
            // Keep today's move meaningful by applying the market's % change to your price.
            var prev = manual
            if let live, live.previousClose > 0 { prev = manual / (live.price / live.previousClose) }
            return PriceInfo(price: manual, previousClose: prev, source: .manual, asOf: nil)
        }
        if let live {
            return PriceInfo(price: live.price, previousClose: live.previousClose, source: .live, asOf: live.marketTime)
        }
        if let manual = asset.manualPrice, manual > 0 {
            return PriceInfo(price: manual, previousClose: manual, source: .manual, asOf: nil)
        }
        if let last = trades.max(by: { $0.date < $1.date }) {
            return PriceInfo(price: last.price, previousClose: last.price, source: .lastTrade, asOf: last.date)
        }
        return nil
    }

    // MARK: Refreshing

    func refresh(assets: [Asset]) async {
        guard !isRefreshing else { return }
        var symbols: Set<String> = [Self.usdCadSymbol]
        for a in assets {
            if a.isGold { symbols.insert(Self.goldFuturesSymbol) } else { symbols.insert(a.symbol) }
        }
        isRefreshing = true
        defer { isRefreshing = false }

        var fetched: [String: Quote] = [:]
        var failures: [String] = []
        await withTaskGroup(of: (String, Quote?).self) { group in
            for s in symbols {
                group.addTask { (s, try? await Self.fetchQuote(symbol: s)) }
            }
            for await (s, q) in group {
                if let q { fetched[s] = q } else { failures.append(s) }
            }
        }

        if fetched.isEmpty {
            lastError = "Couldn't reach the price service. Showing last saved prices."
            return
        }
        quotes.merge(fetched) { _, new in new }
        lastUpdated = Date()
        let shown = failures.filter { $0 != Self.usdCadSymbol && $0 != Self.goldFuturesSymbol }.sorted()
        lastError = failures.isEmpty ? nil : "No price for: \(shown.isEmpty ? failures.sorted().joined(separator: ", ") : shown.joined(separator: ", "))"
        if let data = try? JSONEncoder().encode(quotes) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        UserDefaults.standard.set(lastUpdated, forKey: cacheDateKey)
    }

    // MARK: Network (Yahoo Finance public chart + search endpoints)

    nonisolated private static let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-^"))

    nonisolated static func fetchQuote(symbol: String) async throws -> Quote {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1d&interval=1d")
        else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(ChartResponse.self, from: data)
        guard let meta = decoded.chart.result?.first?.meta, let price = meta.regularMarketPrice else {
            throw URLError(.cannotParseResponse)
        }
        let prev = meta.chartPreviousClose ?? meta.previousClose ?? price
        return Quote(symbol: symbol, price: price, previousClose: prev,
                     currency: meta.currency ?? "USD",
                     name: meta.longName ?? meta.shortName,
                     marketTime: meta.regularMarketTime.map { Date(timeIntervalSince1970: $0) })
    }

    nonisolated static func search(_ query: String) async -> [SymbolSearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 1,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=10&newsCount=0&listsCount=0")
        else { return [] }
        guard let result = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(SearchResponse.self, from: result.0) else { return [] }
        return (decoded.quotes ?? []).compactMap { item in
            guard let symbol = item.symbol else { return nil }
            let type = item.quoteType ?? ""
            guard ["EQUITY", "ETF", "MUTUALFUND", "INDEX"].contains(type.uppercased()) else { return nil }
            return SymbolSearchResult(symbol: symbol,
                                      name: item.longname ?? item.shortname ?? symbol,
                                      exchange: item.exchDisp ?? item.exchange ?? "",
                                      quoteType: type)
        }
    }

    private struct ChartResponse: Decodable {
        struct Chart: Decodable { var result: [Result]? }
        struct Result: Decodable { var meta: Meta }
        struct Meta: Decodable {
            var currency: String?
            var regularMarketPrice: Double?
            var chartPreviousClose: Double?
            var previousClose: Double?
            var regularMarketTime: Double?
            var shortName: String?
            var longName: String?
        }
        var chart: Chart
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            var symbol: String?
            var shortname: String?
            var longname: String?
            var quoteType: String?
            var exchange: String?
            var exchDisp: String?
        }
        var quotes: [Item]?
    }
}

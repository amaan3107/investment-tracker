import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Plain JSON copy of everything in the app, for backups.
struct BackupFile: Codable {
    var version = 1
    var exportedAt = Date()
    var assets: [AssetDTO]

    struct AssetDTO: Codable {
        var symbol: String
        var name: String
        var kind: String
        var currency: String
        var manualPrice: Double?
        var useManualPrice: Bool
        var trades: [TradeDTO]
    }

    struct TradeDTO: Codable {
        var side: String
        var broker: String
        var account: String
        var date: Date
        var quantity: Double
        var price: Double
        var fees: Double
        var totalAmount: Double?
        var amountAfterFees: Double?
        var cadAmount: Double?
        var note: String
    }

    init(assets: [Asset]) {
        self.assets = assets.map { a in
            AssetDTO(symbol: a.symbol, name: a.name, kind: a.kindRaw, currency: a.currencyRaw,
                     manualPrice: a.manualPrice, useManualPrice: a.useManualPrice,
                     trades: a.trades.sorted { $0.date < $1.date }.map { t in
                         TradeDTO(side: t.sideRaw, broker: t.brokerRaw, account: t.accountRaw, date: t.date,
                                  quantity: t.quantity, price: t.price, fees: t.fees,
                                  totalAmount: t.totalAmount, amountAfterFees: t.amountAfterFees,
                                  cadAmount: t.cadAmount, note: t.note)
                     })
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Replaces everything in the app with this backup.
    func restore(into context: ModelContext) throws {
        for a in try context.fetch(FetchDescriptor<Asset>()) { context.delete(a) }
        for t in try context.fetch(FetchDescriptor<Trade>()) { context.delete(t) }
        for dto in assets {
            let asset = Asset(symbol: dto.symbol, name: dto.name,
                              kind: AssetKind(rawValue: dto.kind) ?? .stock,
                              currency: Currency(rawValue: dto.currency) ?? .cad)
            asset.manualPrice = dto.manualPrice
            asset.useManualPrice = dto.useManualPrice
            context.insert(asset)
            for td in dto.trades {
                let account = AccountRef(broker: Broker(rawValue: td.broker) ?? .wealthsimple,
                                         type: AccountType(rawValue: td.account) ?? .tfsa)
                let t = Trade(side: TradeSide(rawValue: td.side) ?? .buy, account: account, date: td.date,
                              quantity: td.quantity, price: td.price, fees: td.fees,
                              totalAmount: td.totalAmount, amountAfterFees: td.amountAfterFees,
                              cadAmount: td.cadAmount, note: td.note)
                context.insert(t)
                t.asset = asset
            }
        }
        try context.save()
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

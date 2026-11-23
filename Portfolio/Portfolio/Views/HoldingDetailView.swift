import SwiftUI
import SwiftData

struct HoldingDetailView: View {
    @Bindable var asset: Asset
    var filter: AccountFilter

    @Environment(PriceService.self) private var prices
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var editingTrade: Trade?
    @State private var addingTrade = false
    @State private var manualText = ""
    @State private var confirmDelete = false

    private var trades: [Trade] {
        asset.trades.filter { filter.includes($0.account) }.sorted { $0.date > $1.date }
    }

    private var position: Position {
        PortfolioBuilder.position(asset: asset, trades: trades, fx: prices.usdToCad,
                                  priceInfo: prices.priceInfo(for: asset, trades: trades))
    }

    private var accountPositions: [(AccountRef, Position)] {
        let groups = Dictionary(grouping: trades, by: \.account)
        return groups.keys.sorted { $0.label < $1.label }.map { account in
            (account, PortfolioBuilder.position(asset: asset, trades: groups[account] ?? [], fx: prices.usdToCad,
                                                priceInfo: prices.priceInfo(for: asset, trades: trades)))
        }
    }

    var body: some View {
        // After a delete the view can redraw once before it closes; don't touch a deleted record.
        if asset.isDeleted || asset.modelContext == nil {
            Color.clear
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let p = position
        let cur = asset.currency
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name).font(.subheadline).foregroundStyle(.secondary)
                    Text(Fmt.money(p.marketValue, cur))
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    Text(filter.label).font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }

            Section("Your position") {
                LabeledValue(label: "Quantity", value: "\(Fmt.quantity(p.quantity, kind: asset.kind)) \(asset.kind.unitLabel)")
                LabeledValue(label: "Average price", value: Fmt.money(p.averagePrice, cur))
                LabeledValue(label: "Book cost", value: Fmt.money(p.bookCost, cur))
                LabeledValue(label: "Market value", value: Fmt.money(p.marketValue, cur))
                HStack {
                    Text("Today's return").foregroundStyle(.secondary)
                    Spacer()
                    ChangeText(amount: p.todayReturn, percent: p.todayReturnPercent, currency: cur, font: .body)
                }
                HStack {
                    Text("Total return").foregroundStyle(.secondary)
                    Spacer()
                    ChangeText(amount: p.totalReturn, percent: p.totalReturnPercent, currency: cur, font: .body)
                }
                if abs(p.realized) > 0.004 {
                    HStack {
                        Text("Realized (sold)").foregroundStyle(.secondary)
                        Spacer()
                        ChangeText(amount: p.realized, percent: nil, currency: cur, font: .body)
                    }
                }
            }

            if cur == .usd {
                Section {
                    LabeledValue(label: "Market value", value: Fmt.money(p.marketValueCAD))
                    LabeledValue(label: "Book cost", value: Fmt.money(p.bookCostCAD))
                    HStack {
                        Text("Total return").foregroundStyle(.secondary)
                        Spacer()
                        ChangeText(amount: p.totalReturnCAD, percent: p.totalReturnCADPercent, font: .body)
                    }
                } header: {
                    Text("In CAD")
                } footer: {
                    Text("Includes currency moves. Add the CAD amount you paid on each trade to match your broker exactly.")
                }
            }

            if asset.isGold {
                Section {
                    LabeledValue(label: "Total invested", value: Fmt.money(p.totalInvested))
                    LabeledValue(label: "Amount after fees", value: Fmt.money(p.totalAfterFees))
                    LabeledValue(label: "Fees paid", value: Fmt.money(p.totalFeesOnBuys))
                    LabeledValue(label: "Total bought", value: "\(Fmt.quantity(p.quantityBought, kind: .gold)) oz")
                    LabeledValue(label: "Average cost / oz (with fees)", value: Fmt.money(p.averageCostPerUnitAllBuys))
                    LabeledValue(label: "Average purchase price / oz", value: Fmt.money(p.averagePurchasePrice))
                } header: {
                    Text("Gold purchases")
                } footer: {
                    Text("Averages are across every gold buy you've entered. Prices are per troy ounce.")
                }
            }

            priceSection(p)

            if accountPositions.count > 1 {
                Section("By account") {
                    ForEach(accountPositions, id: \.0) { account, ap in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.label)
                                Text("\(Fmt.quantity(ap.quantity, kind: asset.kind)) \(asset.kind.unitLabel) · book \(Fmt.money(ap.bookCost, cur))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(Fmt.money(ap.marketValue, cur)).monospacedDigit()
                                ChangeText(amount: ap.totalReturn, percent: ap.totalReturnPercent, currency: cur, font: .caption)
                            }
                        }
                    }
                }
            }

            Section {
                ForEach(trades) { t in
                    Button { editingTrade = t } label: { TradeRow(trade: t, showSymbol: false) }
                        .tint(.primary)
                }
                .onDelete { offsets in
                    let list = trades
                    for i in offsets { TradeStore.delete(list[i], context: context) }
                    if asset.modelContext == nil || asset.trades.isEmpty { dismiss() }
                }
                Button { addingTrade = true } label: { Label("Add transaction", systemImage: "plus") }
            } header: {
                Text("Transactions")
            }

            Section {
                Button("Delete \(asset.displaySymbol) and all its transactions", role: .destructive) {
                    confirmDelete = true
                }
            }
        }
        .navigationTitle(asset.displaySymbol)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await prices.refresh(assets: [asset]) }
        .onAppear { manualText = Fmt.plain(asset.manualPrice) }
        .sheet(item: $editingTrade) { t in TradeFormView(mode: .edit(t)) }
        .sheet(isPresented: $addingTrade) { TradeFormView(mode: .new(asset)) }
        .confirmationDialog("Delete \(asset.displaySymbol)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete everything for \(asset.displaySymbol)", role: .destructive) {
                context.delete(asset)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("This removes all \(asset.trades.count) transactions in every account. It can't be undone unless you have a backup.")
        }
    }

    @ViewBuilder
    private func priceSection(_ p: Position) -> some View {
        let cur = asset.currency
        let live = prices.liveQuote(for: asset)
        Section {
            if let live {
                LabeledValue(label: "Market price", value: Fmt.money(live.price, cur))
                if let time = live.marketTime {
                    LabeledValue(label: "As of", value: Fmt.timestamp(time))
                }
                if asset.isGold, let usd = prices.quotes[PriceService.goldFuturesSymbol] {
                    LabeledValue(label: "In USD", value: Fmt.money(usd.price, .usd))
                    LabeledValue(label: "USD → CAD rate", value: prices.usdToCad.formatted(.number.precision(.fractionLength(4))))
                }
                LabeledValue(label: "Previous close", value: Fmt.money(live.previousClose, cur))
                HStack {
                    Text("Today").foregroundStyle(.secondary)
                    Spacer()
                    ChangeText(amount: live.price - live.previousClose,
                               percent: live.previousClose > 0 ? live.price / live.previousClose - 1 : nil,
                               currency: cur, font: .body)
                }
            } else {
                Text("No live price yet — pull down to refresh.")
                    .foregroundStyle(.secondary)
            }
            Toggle("Use my own price", isOn: $asset.useManualPrice)
            if asset.useManualPrice || live == nil {
                HStack {
                    Text("My price").foregroundStyle(.secondary)
                    Spacer()
                    TextField("0.00", text: $manualText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                        .onChange(of: manualText) { _, new in asset.manualPrice = Fmt.parse(new) }
                }
            }
        } header: {
            Text(asset.isGold ? "Gold price (CAD / oz)" : "Price")
        } footer: {
            Text(priceFooter(p))
        }
    }

    private func priceFooter(_ p: Position) -> String {
        var text: String
        switch p.priceInfo?.source {
        case .live?: text = "Valued at the live market price."
        case .manual?: text = "Valued at your own price."
        case .lastTrade?: text = "No live price, so valued at your last transaction price."
        case nil: text = ""
        }
        if asset.isGold {
            text += " Live gold is the COMEX price in USD per troy ounce × the USD → CAD rate, so it will differ a little from Wealthsimple's buy/sell price. Turn on \"Use my own price\" to type Wealthsimple's price instead."
        } else if asset.kind == .indexFund {
            text += " Mutual-fund prices update once a day after the market closes."
        }
        return text
    }
}

struct TradeRow: View {
    var trade: Trade
    var showSymbol = true

    var body: some View {
        let cur = trade.asset?.currency ?? .cad
        let kind = trade.asset?.kind ?? .stock
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(trade.side.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background((trade.side == .buy ? Color.green : Color.orange).opacity(0.18), in: .rect(cornerRadius: 4))
                        .foregroundStyle(trade.side == .buy ? .green : .orange)
                    if showSymbol, let a = trade.asset {
                        Text(a.displaySymbol).font(.headline)
                    }
                    Text(trade.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(Fmt.quantity(trade.quantity, kind: kind)) \(kind.unitLabel) @ \(Fmt.money(trade.price, cur))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Text(trade.account.label).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.money(trade.cashAmount, cur)).monospacedDigit()
                if trade.fees > 0 {
                    Text("fees \(Fmt.money(trade.fees, cur))").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

enum TradeStore {
    /// Deletes a trade, and its asset too if that was the last trade (keeps the list tidy).
    static func delete(_ trade: Trade, context: ModelContext) {
        let asset = trade.asset
        context.delete(trade)
        try? context.save()
        if let asset, asset.trades.isEmpty {
            context.delete(asset)
            try? context.save()
        }
    }
}

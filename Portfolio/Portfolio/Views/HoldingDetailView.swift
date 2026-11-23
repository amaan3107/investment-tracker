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
                HoldingHeader(asset: asset, position: p, filterLabel: filter.label)
            }

            Section {
                TransactionTable(rows: LotBuilder.rows(trades: trades, isCAD: cur == .cad,
                                                       currentFX: p.fx),
                                 asset: asset, priceInfo: p.priceInfo, fx: p.fx,
                                 onEdit: { editingTrade = $0 },
                                 onDelete: { t in
                                     TradeStore.delete(t, context: context)
                                     if asset.modelContext == nil || asset.trades.isEmpty { dismiss() }
                                 })
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 0))
                Button { addingTrade = true } label: { Label("Add transaction", systemImage: "plus") }
            } header: {
                Text("Transactions")
            } footer: {
                Text("Oldest first. Tap a row to edit it, press and hold to delete. Swipe sideways to see every column.")
            }

            if cur == .usd {
                Section {
                    LabeledValue(label: "USD → CAD today", value: prices.usdToCad.formatted(.number.precision(.fractionLength(4))))
                } footer: {
                    Text("If your broker converted CAD to buy this, add the CAD amount you paid under \"More details\" on each purchase, so your totals match theirs exactly.")
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
                Button("Delete \(asset.displaySymbol) and all its transactions", role: .destructive) {
                    confirmDelete = true
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
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

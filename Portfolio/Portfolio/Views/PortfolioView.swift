import SwiftUI
import SwiftData

struct PortfolioView: View {
    @Environment(PriceService.self) private var prices
    @Query(sort: \Asset.symbol) private var assets: [Asset]
    @AppStorage("accountFilter") private var filterRaw = "all"
    @State private var showingAdd = false

    private var filter: AccountFilter { AccountFilter.decode(filterRaw) }

    private var positions: [Position] {
        PortfolioBuilder.positions(assets: assets, filter: filter, fx: prices.usdToCad) {
            prices.priceInfo(for: $0, trades: $1)
        }
    }

    /// Accounts that have at least one transaction.
    private var knownAccounts: [AccountRef] {
        let all = Set(assets.flatMap { $0.trades.map(\.account) })
        return all.sorted { $0.label < $1.label }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Portfolio")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { filterMenu }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingAdd = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Add transaction")
                    }
                }
                .refreshable { await prices.refresh(assets: assets) }
                .task {
                    let stale = prices.lastUpdated.map { Date().timeIntervalSince($0) > 60 } ?? true
                    if stale && !assets.isEmpty { await prices.refresh(assets: assets) }
                }
                .sheet(isPresented: $showingAdd) {
                    TradeFormView(mode: .new(nil))
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if assets.isEmpty {
            ContentUnavailableView {
                Label("No investments yet", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("Add your first buy from Wealthsimple or Questrade. Everything stays on this phone.")
            } actions: {
                Button("Add transaction") { showingAdd = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            let all = positions
            let open = all.filter(\.isOpen)
            let closed = all.filter { !$0.isOpen }
            List {
                Section {
                    SummaryCard(summary: PortfolioSummary(positions: all), filterLabel: filter.label)
                }
                if let error = prices.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                ForEach(AssetKind.allCases) { kind in
                    let items = open.filter { $0.asset.kind == kind }
                        .sorted { ($0.marketValueCAD ?? 0) > ($1.marketValueCAD ?? 0) }
                    if !items.isEmpty {
                        Section(kind.sectionTitle) {
                            ForEach(items) { p in
                                NavigationLink {
                                    HoldingDetailView(asset: p.asset, filter: filter)
                                } label: {
                                    PositionRow(position: p)
                                }
                            }
                        }
                    }
                }
                if !closed.isEmpty {
                    Section("Closed positions") {
                        ForEach(closed) { p in
                            NavigationLink {
                                HoldingDetailView(asset: p.asset, filter: filter)
                            } label: {
                                ClosedPositionRow(position: p)
                            }
                        }
                    }
                }
                if open.isEmpty && closed.isEmpty {
                    Section {
                        Text("No transactions in \(filter.label).")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    footer
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if prices.isRefreshing {
                Label("Updating prices…", systemImage: "arrow.triangle.2.circlepath")
            } else if let updated = prices.lastUpdated {
                Text("Prices updated \(updated.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("Pull down to load prices")
            }
            Text("USD → CAD \(prices.usdToCad.formatted(.number.precision(.fractionLength(4))))\(prices.hasLiveFX ? "" : " (estimate)")")
            Text("Times show when each price was last updated by the market. Canadian prices are usually ~15 min behind.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .listRowBackground(Color.clear)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Accounts", selection: $filterRaw) {
                Text("All accounts").tag("all")
                ForEach(Broker.allCases) { b in
                    Text("All \(b.label)").tag(AccountFilter.broker(b).encoded)
                }
                ForEach(knownAccounts) { a in
                    Text(a.label).tag(AccountFilter.account(a).encoded)
                }
            }
        } label: {
            Label(filter.label, systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
        }
    }
}

extension AccountFilter {
    var encoded: String {
        switch self {
        case .all: "all"
        case .broker(let b): "broker:\(b.rawValue)"
        case .account(let a): "account:\(a.broker.rawValue):\(a.type.rawValue)"
        }
    }

    static func decode(_ raw: String) -> AccountFilter {
        let parts = raw.split(separator: ":").map(String.init)
        if parts.count == 2, parts[0] == "broker", let b = Broker(rawValue: parts[1]) { return .broker(b) }
        if parts.count == 3, parts[0] == "account", let b = Broker(rawValue: parts[1]),
           let t = AccountType(rawValue: parts[2]) { return .account(AccountRef(broker: b, type: t)) }
        return .all
    }
}

struct SummaryCard: View {
    var summary: PortfolioSummary
    var filterLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(filterLabel).font(.subheadline).foregroundStyle(.secondary)
                Text(Fmt.money(summary.marketValue))
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Today's return").foregroundStyle(.secondary)
                    ChangeText(amount: summary.todayReturn, percent: summary.todayReturnPercent)
                }
                GridRow {
                    Text("Total return").foregroundStyle(.secondary)
                    ChangeText(amount: summary.totalReturn, percent: summary.totalReturnPercent)
                }
                GridRow {
                    Text("Book cost").foregroundStyle(.secondary)
                    Text(Fmt.money(summary.bookCost)).monospacedDigit()
                }
                if abs(summary.realized) > 0.004 {
                    GridRow {
                        Text("Realized (sold)").foregroundStyle(.secondary)
                        ChangeText(amount: summary.realized, percent: nil)
                    }
                }
            }
            .font(.subheadline)
            Text("All amounts in CAD")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

struct PositionRow: View {
    var position: Position

    var body: some View {
        let a = position.asset
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(a.displaySymbol).font(.headline)
                    if a.currency == .usd {
                        Text("USD").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.blue.opacity(0.15), in: .rect(cornerRadius: 4))
                            .foregroundStyle(.blue)
                    }
                    if position.priceInfo?.source == .manual {
                        Image(systemName: "pencil.circle").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(a.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("\(Fmt.quantity(position.quantity, kind: a.kind)) \(a.kind.unitLabel) · avg \(Fmt.money(position.averagePrice, a.currency))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let info = position.priceInfo {
                    Text("\(Fmt.money(info.price, a.currency))\(a.isGold ? "/oz" : "") · \(Fmt.asOf(info))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.money(position.marketValue, a.currency))
                    .font(.headline.monospacedDigit())
                ChangeText(amount: position.todayReturn, percent: position.todayReturnPercent,
                           currency: a.currency, font: .caption)
                ChangeText(amount: position.totalReturn, percent: position.totalReturnPercent,
                           currency: a.currency, font: .caption)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ClosedPositionRow: View {
    var position: Position

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(position.asset.displaySymbol).font(.headline)
                Text(position.asset.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("Realized").font(.caption).foregroundStyle(.secondary)
                ChangeText(amount: position.realized, percent: nil, currency: position.asset.currency, font: .subheadline)
            }
        }
    }
}

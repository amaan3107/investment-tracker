import SwiftUI
import SwiftData

struct TradeFormView: View {
    enum Mode {
        case new(Asset?)   // optional preset asset
        case edit(Trade)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(PriceService.self) private var prices
    @Query private var assets: [Asset]

    // Investment
    @State private var kind: AssetKind
    @State private var symbol: String
    @State private var name: String
    @State private var currency: Currency
    @State private var searchText = ""
    @State private var results: [SymbolSearchResult] = []
    @State private var searching = false

    // Trade
    @State private var side: TradeSide
    @State private var broker: Broker
    @State private var accountType: AccountType
    @State private var date: Date
    @State private var quantityText: String
    @State private var priceText: String
    @State private var feesText: String
    @State private var totalText: String
    @State private var afterFeesText: String
    @State private var cadText: String
    @State private var note: String
    @State private var showMoreDetails: Bool

    init(mode: Mode) {
        self.mode = mode
        let d = UserDefaults.standard
        var k = AssetKind.stock, sym = "", nm = "", cur = Currency.cad
        var sd = TradeSide.buy
        var br = Broker(rawValue: d.string(forKey: "lastBroker") ?? "") ?? .wealthsimple
        var ac = AccountType(rawValue: d.string(forKey: "lastAccount") ?? "") ?? .tfsa
        var dt = Date()
        var q = "", p = "", f = "", tot = "", after = "", cad = "", nt = ""

        switch mode {
        case .new(let asset):
            if let asset {
                k = asset.kind; sym = asset.symbol; nm = asset.name; cur = asset.currency
                // Default to the account this holding already lives in.
                if let last = asset.trades.max(by: { $0.date < $1.date }) {
                    br = last.account.broker; ac = last.account.type
                }
            }
        case .edit(let t):
            if let a = t.asset { k = a.kind; sym = a.symbol; nm = a.name; cur = a.currency }
            sd = t.side; br = t.account.broker; ac = t.account.type; dt = t.date
            q = Fmt.plain(t.quantity); p = Fmt.plain(t.price); nt = t.note
            f = t.fees > 0 ? Fmt.plain(t.fees) : ""
            tot = Fmt.plain(t.totalAmount)
            after = Fmt.plain(t.amountAfterFees)
            cad = Fmt.plain(t.cadAmount)
        }
        _kind = State(initialValue: k); _symbol = State(initialValue: sym)
        _name = State(initialValue: nm); _currency = State(initialValue: cur)
        _side = State(initialValue: sd); _broker = State(initialValue: br)
        _accountType = State(initialValue: ac); _date = State(initialValue: dt)
        _quantityText = State(initialValue: q); _priceText = State(initialValue: p)
        _feesText = State(initialValue: f); _totalText = State(initialValue: tot)
        _afterFeesText = State(initialValue: after); _cadText = State(initialValue: cad)
        _note = State(initialValue: nt)
        // Open the extras when editing a trade that already uses them.
        _showMoreDetails = State(initialValue: !f.isEmpty || !tot.isEmpty || !cad.isEmpty || !nt.isEmpty)
    }

    private var isEditing: Bool { if case .edit = mode { true } else { false } }
    private var presetAsset: Asset? {
        switch mode {
        case .new(let a): a
        case .edit(let t): t.asset
        }
    }
    private var canChangeInvestment: Bool { presetAsset == nil }
    private var isGold: Bool { kind == .gold }

    // MARK: Parsed values

    private var quantity: Double? { Fmt.parse(quantityText) }
    private var price: Double? { Fmt.parse(priceText) }
    private var fees: Double? { Fmt.parse(feesText) }
    private var total: Double? { Fmt.parse(totalText) }
    private var afterFees: Double? { Fmt.parse(afterFeesText) }
    private var cad: Double? { Fmt.parse(cadText) }

    /// Gold buy: fee = amount invested − amount after fees.
    private var goldFee: Double? {
        guard let total, let afterFees else { return nil }
        return max(0, total - afterFees)
    }

    /// The price that will be saved (gold can work it out if you leave it blank).
    private var effectivePrice: Double? {
        if let price, price > 0 { return price }
        guard isGold, let q = quantity, q > 0 else { return nil }
        if side == .buy, let base = afterFees ?? total { return base / q }
        if side == .sell, let total { return (total + (fees ?? 0)) / q }
        return nil
    }

    private var validationMessage: String? {
        if !isGold && symbol.isEmpty { return "Choose an investment." }
        guard let q = quantity, q > 0 else { return isGold ? "Enter the quantity in ounces." : "Enter the quantity (number of shares)." }
        if isGold && side == .buy && (total ?? 0) <= 0 { return "Enter the amount you invested." }
        if isGold && side == .sell && (total ?? 0) <= 0 { return "Enter the amount you received." }
        if (effectivePrice ?? 0) <= 0 { return "Enter the price." }
        return nil
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                investmentSection
                if isGold {
                    Section {
                        sidePicker
                        DatePicker("Date", selection: $date, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: .date)
                        brokerPicker
                        accountPicker
                    }
                    goldFields
                    Section("Note") {
                        TextField("Optional", text: $note, axis: .vertical)
                    }
                } else {
                    securityFields
                    Section("Account") {
                        brokerPicker
                        accountPicker
                    }
                    moreDetails
                }
                if let msg = validationMessage {
                    Section { Text(msg).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit transaction" : "New transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(validationMessage != nil)
                }
                // The number pad has no return key, so give it a way to close.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }.fontWeight(.semibold)
                }
            }
            .onChange(of: kind) { _, newKind in
                if newKind == .gold {
                    currency = .cad
                    if !isEditing && presetAsset == nil { broker = .wealthsimple }
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var investmentSection: some View {
        if canChangeInvestment {
            Section {
                Picker("Investment type", selection: $kind) {
                    ForEach(AssetKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if isGold {
                    Label("Physical gold, priced per troy ounce in CAD", systemImage: "circle.hexagongrid.fill")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if !symbol.isEmpty {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(symbol).font(.headline)
                            if !name.isEmpty { Text(name).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Change") { symbol = ""; name = ""; searchText = "" }
                            .buttonStyle(.borderless)
                    }
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) { Text($0.rawValue).tag($0) }
                    }
                } else {
                    TextField("Search: XEQT, VFV, Apple, Shopify…", text: $searchText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .task(id: searchText) { await runSearch() }
                    if searching { ProgressView() }
                    ForEach(results) { r in
                        Button { select(r) } label: {
                            VStack(alignment: .leading) {
                                Text(r.symbol).font(.headline)
                                Text("\(r.name) · \(r.exchange)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                    let typed = searchText.trimmingCharacters(in: .whitespaces).uppercased()
                    if !typed.isEmpty && !results.contains(where: { $0.symbol == typed }) {
                        Button("Use “\(typed)” as typed") {
                            symbol = typed; name = typed; currency = Currency.guess(for: typed)
                        }
                    }
                }
            } header: {
                Text("Investment")
            } footer: {
                if !isGold && symbol.isEmpty {
                    Text("Canadian listings end in .TO (e.g. XEQT.TO). US listings have no suffix (e.g. AAPL).")
                }
            }
        } else {
            Section("Investment") {
                VStack(alignment: .leading) {
                    Text(isGold ? "Physical Gold" : symbol).font(.headline)
                    Text(isGold ? "Priced per troy ounce, CAD" : "\(name) · \(currency.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sidePicker: some View {
        Picker("Type", selection: $side) {
            ForEach(TradeSide.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var brokerPicker: some View {
        Picker("Broker", selection: $broker) {
            ForEach(Broker.allCases) { Text($0.label).tag($0) }
        }
    }

    private var accountPicker: some View {
        Picker("Account", selection: $accountType) {
            ForEach(AccountType.allCases) { Text($0.label).tag($0) }
        }
    }

    /// Google Finance–style: quantity, purchase date, purchase price.
    @ViewBuilder
    private var securityFields: some View {
        let currencyNote = currency == .usd ? " (USD)" : ""
        Section {
            sidePicker
            NumberField(label: "Quantity", text: $quantityText, placeholder: "0")
            DatePicker(side == .buy ? "Purchase date" : "Sale date", selection: $date,
                       in: ...Date.now.addingTimeInterval(86_400), displayedComponents: .date)
            NumberField(label: (side == .buy ? "Purchase price" : "Sale price") + currencyNote, text: $priceText)
            if let total = autoTotal, total > 0 {
                LabeledValue(label: side == .buy ? "Total cost" : "Total received", value: Fmt.money(total, currency))
            }
        } header: {
            Text("Transaction")
        } footer: {
            Text("Price is per share. You can find it on your Wealthsimple or Questrade order.")
        }
    }

    /// Rarely needed extras, kept out of the way.
    private var moreDetails: some View {
        Section {
            DisclosureGroup("More details (optional)", isExpanded: $showMoreDetails) {
                NumberField(label: "Fees / commission", text: $feesText, placeholder: "0.00")
                NumberField(label: side == .buy ? "Total paid, if different" : "Total received, if different",
                            text: $totalText, placeholder: Fmt.plain(autoTotal))
                if currency == .usd {
                    NumberField(label: side == .buy ? "CAD paid" : "CAD received", text: $cadText, placeholder: "optional")
                }
                TextField("Note", text: $note, axis: .vertical)
            }
        } footer: {
            Text(currency == .usd
                 ? "Add a commission if your broker charged one. If your broker converted CAD to buy this, enter the CAD amount so your CAD totals match theirs."
                 : "Add a commission if your broker charged one (Wealthsimple usually doesn't).")
        }
    }

    private var autoTotal: Double? {
        guard let q = quantity, let p = price else { return nil }
        return side == .buy ? q * p + (fees ?? 0) : q * p - (fees ?? 0)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @ViewBuilder
    private var goldFields: some View {
        if side == .buy {
            Section {
                NumberField(label: "Amount invested (CAD)", text: $totalText)
                NumberField(label: "Price per oz (CAD)", text: $priceText,
                            placeholder: prices.goldQuoteCAD.map { Fmt.plain(($0.price * 100).rounded() / 100) } ?? "0.00")
                NumberField(label: "Quantity (oz)", text: $quantityText, placeholder: "0.000000")
                NumberField(label: "Amount after fees (CAD)", text: $afterFeesText, placeholder: "optional")
                if let goldFee {
                    LabeledValue(label: "Fee", value: Fmt.money(goldFee))
                }
                if let q = quantity, q > 0, let t = total {
                    LabeledValue(label: "Your cost per oz (with fees)", value: Fmt.money(t / q))
                }
            } header: {
                Text("Gold purchase")
            } footer: {
                Text("Enter these from your Wealthsimple order. Book cost uses the amount invested, so fees are included. If you leave the price blank it's worked out from the amount and quantity.")
            }
        } else {
            Section {
                NumberField(label: "Quantity sold (oz)", text: $quantityText, placeholder: "0.000000")
                NumberField(label: "Price per oz (CAD)", text: $priceText)
                NumberField(label: "Amount received (CAD)", text: $totalText)
                NumberField(label: "Fees (CAD)", text: $feesText, placeholder: "0.00")
            } header: {
                Text("Gold sale")
            }
        }
    }

    // MARK: Actions

    private func runSearch() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard q.count >= 1 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(350))   // debounce typing
        guard !Task.isCancelled else { return }
        searching = true
        let found = await PriceService.search(q)
        guard !Task.isCancelled else { return }
        searching = false
        results = found
    }

    private func select(_ r: SymbolSearchResult) {
        symbol = r.symbol
        name = r.name
        if kind != .gold { kind = r.suggestedKind }
        currency = Currency.guess(for: r.symbol)
        results = []
        let s = r.symbol
        Task {
            if let q = try? await PriceService.fetchQuote(symbol: s), symbol == s,
               let c = Currency(rawValue: q.currency.uppercased()) {
                currency = c
            }
        }
    }

    private func save() {
        guard validationMessage == nil, let q = quantity, let p = effectivePrice else { return }
        let account = AccountRef(broker: broker, type: accountType)

        var feeValue = fees ?? 0
        var totalValue = total
        var afterValue: Double? = nil
        var cadValue: Double? = nil
        if isGold {
            if side == .buy {
                afterValue = afterFees
                feeValue = goldFee ?? 0
            }
        } else if currency == .usd {
            cadValue = cad
        }
        if totalValue != nil && totalValue! <= 0 { totalValue = nil }

        switch mode {
        case .edit(let t):
            t.side = side; t.account = account; t.date = date
            t.quantity = q; t.price = p; t.fees = feeValue
            t.totalAmount = totalValue; t.amountAfterFees = afterValue; t.cadAmount = cadValue
            t.note = note
            if let a = t.asset, !isGold { a.currency = currency }
        case .new(let preset):
            let asset = preset ?? findOrCreateAsset()
            if !isGold && preset == nil { asset.currency = currency }
            let t = Trade(side: side, account: account, date: date, quantity: q, price: p,
                          fees: feeValue, totalAmount: totalValue, amountAfterFees: afterValue,
                          cadAmount: cadValue, note: note)
            context.insert(t)
            t.asset = asset
        }
        try? context.save()
        UserDefaults.standard.set(broker.rawValue, forKey: "lastBroker")
        UserDefaults.standard.set(accountType.rawValue, forKey: "lastAccount")
        let all = assets
        Task { await prices.refresh(assets: all) }
        dismiss()
    }

    private func findOrCreateAsset() -> Asset {
        let sym = isGold ? Asset.goldSymbol : symbol.uppercased()
        if let existing = assets.first(where: { $0.symbol.uppercased() == sym }) { return existing }
        let asset = isGold
            ? Asset(symbol: Asset.goldSymbol, name: "Physical Gold", kind: .gold, currency: .cad)
            : Asset(symbol: sym, name: name.isEmpty ? sym : name, kind: kind, currency: currency)
        context.insert(asset)
        return asset
    }
}

/// A labelled decimal input row.
struct NumberField: View {
    var label: String
    @Binding var text: String
    var placeholder: String = "0.00"

    var body: some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}

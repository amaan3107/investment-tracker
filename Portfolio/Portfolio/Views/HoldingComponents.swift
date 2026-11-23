import SwiftUI

/// Top of a holding's page: market value, money put in, quantity and total gain/loss.
/// US stocks show CAD first (like Google Finance), with the USD amount underneath.
struct HoldingHeader: View {
    var asset: Asset
    var position: Position
    var filterLabel: String

    var body: some View {
        let p = position
        let isUSD = asset.currency == .usd
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(Fmt.money(isUSD ? p.marketValueCAD : p.marketValue))
                    .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text("Market value · \(filterLabel)" + (isUSD ? " · \(Fmt.money(p.marketValue, .usd))" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
                GridRow {
                    stat("Total invested") {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Fmt.money(isUSD ? p.bookCostCAD : p.bookCost))
                            if isUSD { usdNote(Fmt.money(p.bookCost, .usd)) }
                        }
                    }
                    stat("Total gain/loss") {
                        VStack(alignment: .leading, spacing: 1) {
                            let gain = isUSD ? p.totalReturnCAD : p.totalReturn
                            let pct = isUSD ? p.totalReturnCADPercent : p.totalReturnPercent
                            Text(Fmt.signedMoney(gain) + (pct.map { "  \(Fmt.percent($0))" } ?? ""))
                                .foregroundStyle(Fmt.color(gain))
                            if isUSD { usdNote(Fmt.signedMoney(p.totalReturn, .usd)) }
                        }
                    }
                }
                GridRow {
                    stat("Quantity") { Text("\(Fmt.quantity(p.quantity, kind: asset.kind)) \(asset.kind.unitLabel)") }
                    stat("Average price") { Text(Fmt.money(p.averagePrice, asset.currency)) }
                }
                GridRow {
                    stat("Price") {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Fmt.money(p.price, asset.currency))
                            if let info = p.priceInfo {
                                Text(Fmt.asOf(info)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if abs(p.realized) > 0.004 {
                        stat("Realized (sold)") {
                            let r = isUSD ? p.realizedCAD : p.realized
                            Text(Fmt.signedMoney(r)).foregroundStyle(Fmt.color(r))
                        }
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
            if isUSD {
                Text("In CAD at today's rate (USD → CAD), like Google Finance. Purchases where you entered the CAD you paid use that amount instead.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func usdNote(_ text: String) -> some View {
        Text(text).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
    }

    private func stat<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            value().font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Google Finance–style table of every buy and sell for a holding, oldest first.
struct TransactionTable: View {
    var rows: [LotRow]
    var asset: Asset
    var priceInfo: PriceInfo?
    /// CAD per unit of the stock's currency today.
    var fx: Double
    var onEdit: (Trade) -> Void
    var onDelete: (Trade) -> Void

    private var isUSD: Bool { asset.currency == .usd }

    private enum Col {
        static let date: CGFloat = 112, price: CGFloat = 96, qty: CGFloat = 80
        static let gain: CGFloat = 120, value: CGFloat = 108
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                Divider()
                ForEach(rows) { row in
                    Button { onEdit(row.trade) } label: { rowView(row) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { onEdit(row.trade) } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { onDelete(row.trade) } label: { Label("Delete", systemImage: "trash") }
                        }
                    Divider()
                }
            }
            .padding(.trailing, 12)
        }
    }

    private var headerRow: some View {
        let unit = asset.isGold ? "oz" : "share"
        let cad = isUSD ? " (CAD)" : ""
        return HStack(alignment: .bottom, spacing: 0) {
            heading("Purchase date", width: Col.date, align: .leading)
            heading("Price / \(unit)", width: Col.price)
            heading("Quantity", width: Col.qty)
            heading("Total gain/loss" + cad, width: Col.gain)
            heading("Market value" + cad, width: Col.value)
        }
        .padding(.bottom, 6)
    }

    private func heading(_ text: String, width: CGFloat, align: Alignment = .trailing) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(align == .leading ? .leading : .trailing)
            .frame(width: width, alignment: align)
    }

    private func rowView(_ row: LotRow) -> some View {
        let t = row.trade
        let gain = row.totalGain(priceInfo, inCAD: isUSD, fx: fx)
        let pct = row.totalGainPercent(priceInfo, inCAD: isUSD, fx: fx)
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(t.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 4) {
                    if row.isSell {
                        Text("SOLD").font(.caption2.weight(.bold))
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: .rect(cornerRadius: 3))
                            .foregroundStyle(.orange)
                    }
                    Text(t.account.label).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(width: Col.date, alignment: .leading)

            Text(Fmt.money(t.price, asset.currency))
                .frame(width: Col.price, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 2) {
                Text((row.isSell ? "−" : "") + Fmt.quantity(row.isSell ? t.quantity : row.remainingQuantity, kind: asset.kind))
                if !row.isSell, row.remainingQuantity + 1e-9 < t.quantity {
                    Text("of \(Fmt.quantity(t.quantity, kind: asset.kind))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: Col.qty, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.signedMoney(gain))
                if let pct { Text(Fmt.percent(pct)).font(.caption2) }
                if row.isSell { Text("realized").font(.caption2).foregroundStyle(.secondary) }
            }
            .foregroundStyle(Fmt.color(gain))
            .frame(width: Col.gain, alignment: .trailing)

            Text(Fmt.money(row.marketValue(priceInfo, inCAD: isUSD, fx: fx)))
                .frame(width: Col.value, alignment: .trailing)
        }
        .font(.subheadline.monospacedDigit())
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

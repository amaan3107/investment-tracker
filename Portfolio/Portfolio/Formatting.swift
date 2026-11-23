import SwiftUI

enum Fmt {
    static func money(_ value: Double?, _ currency: Currency = .cad) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: currency.rawValue).locale(Locale(identifier: "en_CA")))
    }

    static func signedMoney(_ value: Double?, _ currency: Currency = .cad) -> String {
        guard let value else { return "—" }
        let sign = value > 0.0049 ? "+" : (value < -0.0049 ? "−" : "")
        return sign + money(abs(value), currency)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "" }
        let sign = value > 0.00005 ? "+" : (value < -0.00005 ? "−" : "")
        return sign + abs(value).formatted(.percent.precision(.fractionLength(2)))
    }

    static func quantity(_ value: Double, kind: AssetKind) -> String {
        let digits = kind == .gold ? 0...6 : 0...4
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    /// Plain number for editing fields.
    static func plain(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...6)).grouping(.never))
    }

    /// Parses user input like "1,234.50" or "$500".
    static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    /// "as of 1:32 PM" for today's prices, "as of Nov 21, 4:00 PM" for older ones.
    static func asOf(_ info: PriceInfo?) -> String {
        guard let info else { return "" }
        switch info.source {
        case .manual: return "your price"
        case .lastTrade: return "last trade price"
        case .live:
            guard let date = info.asOf else { return "live" }
            return "as of " + timestamp(date)
        }
    }

    static func timestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func color(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value > 0.0049 { return .green }
        if value < -0.0049 { return .red }
        return .secondary
    }
}

/// "+$12.34 (+1.20%)" coloured green / red.
struct ChangeText: View {
    var amount: Double?
    var percent: Double?
    var currency: Currency = .cad
    var font: Font = .subheadline

    var body: some View {
        let pct = Fmt.percent(percent)
        Text(Fmt.signedMoney(amount, currency) + (pct.isEmpty ? "" : " (\(pct))"))
            .font(font.monospacedDigit())
            .foregroundStyle(Fmt.color(amount))
    }
}

struct LabeledValue: View {
    var label: String
    var value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(color)
        }
    }
}

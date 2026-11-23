import SwiftUI
import Charts

/// Portfolio worth over time vs the money you put in, with Google Finance–style ranges
/// and drag-to-inspect.
struct PortfolioChartCard: View {
    var points: [HistoryPoint]
    var isLoading: Bool

    @AppStorage("chartRange") private var rangeRaw = ChartRange.all.rawValue
    @State private var selectedDate: Date?

    private var range: ChartRange { ChartRange(rawValue: rangeRaw) ?? .all }

    var body: some View {
        let today = DayKey.day(.now)
        let shown = range.slice(points, today: today)
        // If the range reaches back to your first purchase, the change is simply everything so far.
        let coversAll = range == .all || shown.first?.day == points.first?.day
        let change = rangeChange(shown, coversAll: coversAll)
        let color: Color = (change?.amount ?? 0) >= -0.004 ? .green : .red

        VStack(alignment: .leading, spacing: 12) {
            header(shown, change: change, color: color)

            if shown.count >= 2 {
                chart(shown, color: color)
                    .frame(height: 210)
            } else {
                placeholder
            }

            HStack(spacing: 16) {
                legendItem("Worth", color: color, dashed: false)
                legendItem("Money put in", color: .secondary, dashed: true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Picker("Range", selection: $rangeRaw) {
                ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 6)
        .onChange(of: rangeRaw) { _, _ in selectedDate = nil }
    }

    // MARK: Header

    @ViewBuilder
    private func header(_ shown: [HistoryPoint], change: (amount: Double, percent: Double?)?, color: Color) -> some View {
        if let p = selectedPoint(in: shown) {
            // While dragging: that day's numbers.
            VStack(alignment: .leading, spacing: 3) {
                Text(p.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
                Text("Worth \(Fmt.money(p.value))").font(.headline.monospacedDigit())
                HStack(spacing: 10) {
                    Text("Put in \(Fmt.money(p.invested))").foregroundStyle(.secondary)
                    ChangeText(amount: p.gain, percent: p.invested > 0 ? p.gain / p.invested : nil, font: .subheadline)
                }
                .font(.subheadline.monospacedDigit())
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("Performance").font(.headline)
                if let change {
                    HStack(spacing: 4) {
                        ChangeText(amount: change.amount, percent: change.percent, font: .subheadline)
                        Text(range.caption + (abs(shown.last?.realized ?? 0) > 0.004 ? ", incl. sales" : ""))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Gain made during the range: not counting new money you added, and counting sales
    /// (selling locks a gain in; it isn't a loss).
    private func rangeChange(_ shown: [HistoryPoint], coversAll: Bool) -> (amount: Double, percent: Double?)? {
        guard let last = shown.last else { return nil }
        if coversAll || shown.count < 2 {
            return (last.totalGain, last.invested > 0 ? last.totalGain / last.invested : nil)
        }
        let first = shown[0]
        let amount = last.totalGain - first.totalGain
        let base = first.value > 0 ? first.value : last.invested
        return (amount, base > 0 ? amount / base : nil)
    }

    private func selectedPoint(in shown: [HistoryPoint]) -> HistoryPoint? {
        guard let selectedDate, !shown.isEmpty else { return nil }
        return shown.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    // MARK: Chart

    private func chart(_ shown: [HistoryPoint], color: Color) -> some View {
        let all = shown.map(\.value) + shown.map(\.invested)
        let lo = all.min() ?? 0, hi = all.max() ?? 1
        let pad = max((hi - lo) * 0.12, hi * 0.01, 1)
        let bottom = max(0, lo - pad), top = hi + pad
        let selected = selectedPoint(in: shown)
        let spanDays = shown.first.map { Calendar.current.dateComponents([.day], from: $0.date, to: shown.last!.date).day ?? 0 } ?? 0

        return Chart {
            ForEach(shown) { p in
                AreaMark(x: .value("Date", p.date),
                         yStart: .value("Bottom", bottom),
                         yEnd: .value("Worth", p.value),
                         series: .value("Series", "Area"))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", p.date), y: .value("Worth", p.value),
                         series: .value("Series", "Worth"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                LineMark(x: .value("Date", p.date), y: .value("Put in", p.invested),
                         series: .value("Series", "Invested"))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            }
            if let selected {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                PointMark(x: .value("Date", selected.date), y: .value("Worth", selected.value))
                    .foregroundStyle(color)
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: bottom...top)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: spanDays > 200
                               ? .dateTime.month(.abbreviated).year(.twoDigits)
                               : .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("$" + v.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))))
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .accessibilityLabel("Portfolio worth over time compared with money put in")
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 8) {
            if isLoading {
                ProgressView()
                Text("Loading price history…")
            } else {
                Image(systemName: "chart.xyaxis.line").font(.title2)
                Text("The chart fills in after your first full day of trading.")
                    .multilineTextAlignment(.center)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private func legendItem(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            Path { p in p.move(to: CGPoint(x: 0, y: 4)); p.addLine(to: CGPoint(x: 16, y: 4)) }
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [4, 3] : []))
                .frame(width: 16, height: 8)
            Text(title)
        }
    }
}

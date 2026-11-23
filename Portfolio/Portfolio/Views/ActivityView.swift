import SwiftUI
import SwiftData

struct ActivityView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trade.date, order: .reverse) private var trades: [Trade]
    @State private var search = ""
    @State private var editing: Trade?
    @State private var adding = false

    private var filtered: [Trade] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return trades }
        return trades.filter { t in
            let a = t.asset
            return (a?.displaySymbol.lowercased().contains(q) ?? false)
                || (a?.name.lowercased().contains(q) ?? false)
                || t.account.label.lowercased().contains(q)
                || t.note.lowercased().contains(q)
        }
    }

    private var groupedByMonth: [(String, [Trade])] {
        let groups = Dictionary(grouping: filtered) { t in
            Calendar.current.dateInterval(of: .month, for: t.date)?.start ?? t.date
        }
        return groups.keys.sorted(by: >).map { key in
            (key.formatted(.dateTime.month(.wide).year()), groups[key] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if trades.isEmpty {
                    ContentUnavailableView("No transactions", systemImage: "list.bullet.rectangle",
                                           description: Text("Buys and sells you add will show up here."))
                } else {
                    List {
                        ForEach(groupedByMonth, id: \.0) { month, items in
                            Section(month) {
                                ForEach(items) { t in
                                    Button { editing = t } label: { TradeRow(trade: t) }
                                        .tint(.primary)
                                        .swipeActions {
                                            Button("Delete", role: .destructive) {
                                                TradeStore.delete(t, context: context)
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .searchable(text: $search, prompt: "Symbol, account or note")
                }
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { TradeFormView(mode: .edit($0)) }
            .sheet(isPresented: $adding) { TradeFormView(mode: .new(nil)) }
        }
    }
}

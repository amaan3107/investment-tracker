import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(PriceService.self) private var prices
    @Query private var assets: [Asset]
    @AppStorage("faceIDEnabled") private var faceIDEnabled = true

    @State private var exportDoc: BackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingRestore: BackupFile?
    @State private var message: String?

    private var tradeCount: Int { assets.reduce(0) { $0 + $1.trades.count } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Lock with Face ID", isOn: $faceIDEnabled)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Your holdings and transactions are stored only on this iPhone. The app has no account and no server. To get prices it sends ticker symbols (like XEQT.TO) to Yahoo Finance — never your quantities, costs or accounts.")
                }

                Section {
                    Button {
                        do {
                            let data = try BackupFile.encoder.encode(BackupFile(assets: assets))
                            exportDoc = BackupDocument(data: data)
                            showingExporter = true
                        } catch {
                            message = "Couldn't create the backup: \(error.localizedDescription)"
                        }
                    } label: {
                        Label("Export backup", systemImage: "square.and.arrow.up")
                    }
                    .disabled(assets.isEmpty)
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Restore from backup", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("\(tradeCount) transactions in \(assets.count) holdings. Export a backup now and then and keep it in Files or iCloud Drive — if the app is ever deleted, its data goes with it.")
                }

                Section("Prices") {
                    LabeledValue(label: "USD → CAD", value: prices.usdToCad.formatted(.number.precision(.fractionLength(4))))
                    if let gold = prices.goldQuoteCAD {
                        LabeledValue(label: "Gold (CAD / oz)", value: Fmt.money(gold.price))
                    }
                    if let updated = prices.lastUpdated {
                        LabeledValue(label: "Last updated", value: updated.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("Refresh prices now") {
                        let all = assets
                        Task { await prices.refresh(assets: all) }
                    }
                }

                Section {
                    Text("Book cost uses the average-cost method (ACB), per account, the same way Canadian brokers report it. Total gain/loss is what your holdings are worth now minus what you paid. US stocks are shown in CAD at today's exchange rate, like Google Finance, unless you entered the CAD you actually paid on a purchase.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("How returns are calculated")
                }
            }
            .navigationTitle("Settings")
            .fileExporter(isPresented: $showingExporter, document: exportDoc, contentType: .json,
                          defaultFilename: "portfolio-backup-\(Date().formatted(.iso8601.year().month().day()))") { result in
                if case .failure(let error) = result { message = "Export failed: \(error.localizedDescription)" }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        pendingRestore = try BackupFile.decoder.decode(BackupFile.self, from: data)
                    } catch {
                        message = "That file isn't a Portfolio backup."
                    }
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
            .alert("Replace all data?", isPresented: Binding(get: { pendingRestore != nil },
                                                             set: { if !$0 { pendingRestore = nil } })) {
                Button("Replace", role: .destructive) {
                    guard let backup = pendingRestore else { return }
                    do {
                        try backup.restore(into: context)
                        let count = backup.assets.reduce(0) { $0 + $1.trades.count }
                        message = "Restored \(count) transactions."
                        let all = (try? context.fetch(FetchDescriptor<Asset>())) ?? []
                        Task { await prices.refresh(assets: all) }
                    } catch {
                        message = "Restore failed: \(error.localizedDescription)"
                    }
                    pendingRestore = nil
                }
                Button("Cancel", role: .cancel) { pendingRestore = nil }
            } message: {
                if let b = pendingRestore {
                    Text("The backup from \(b.exportedAt.formatted(date: .abbreviated, time: .shortened)) will replace the \(tradeCount) transactions currently in the app.")
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

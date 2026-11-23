import SwiftUI
import SwiftData
import LocalAuthentication

@main
struct PortfolioApp: App {
    @State private var prices = PriceService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(prices)
        }
        .modelContainer(for: [Asset.self, Trade.self])
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("faceIDEnabled") private var faceIDEnabled = true
    @State private var locked = true
    @State private var authenticating = false
    @State private var promptWhenActive = false
    @State private var demoLoaded = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            TabView {
                PortfolioView()
                    .tabItem { Label("Portfolio", systemImage: "chart.pie.fill") }
                ActivityView()
                    .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            if faceIDEnabled && locked {
                LockScreen(unlock: authenticate)
                    .transition(.opacity)
            }
        }
        .onAppear {
            #if DEBUG
            if DemoData.isRequested && !demoLoaded {
                demoLoaded = true
                DemoData.load(into: modelContext)
            }
            #endif
            if faceIDEnabled { authenticate() } else { locked = false }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                if faceIDEnabled { locked = true; promptWhenActive = true }
            case .active:
                // Only prompt after coming back from the background, so cancelling
                // the Face ID sheet doesn't immediately re-open it.
                if promptWhenActive { promptWhenActive = false; authenticate() }
            default:
                break
            }
        }
    }

    private func authenticate() {
        guard !authenticating else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No Face ID or passcode set up on this device — don't lock you out.
            locked = false
            return
        }
        authenticating = true
        Task {
            let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                        localizedReason: "Unlock your portfolio")) ?? false
            authenticating = false
            withAnimation { if ok { locked = false } }
        }
    }
}

struct LockScreen: View {
    var unlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Portfolio is locked")
                    .font(.title3.weight(.semibold))
                Button("Unlock", action: unlock)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

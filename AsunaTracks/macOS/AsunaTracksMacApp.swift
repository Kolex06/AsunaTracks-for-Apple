#if os(macOS)
import SwiftUI
import AppKit

@main
struct AsunaTracksMacApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    @FocusedValue(\.asunaNavigation) private var navigate
    @AppStorage("appearance") private var appearance = "dark"
    var body: some Scene {
        WindowGroup("AsunaTracks", id: "main") {
            MacRootView()
                .environment(store)
                .environment(\.accountTheme, store.user?.accountTheme ?? AccountTheme())
                .tint((store.user?.accountTheme ?? AccountTheme()).accent)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
                .frame(minWidth: 850, minHeight: 620)
                .task { if !store.accountLoaded { await store.bootstrap() } }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    if store.accountLoaded { try? await store.refreshList() }
                    // Refresh on return from website settings, then while this window stays active.
                    while !Task.isCancelled {
                        if store.accountLoaded { await store.refreshAccountTheme() }
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    }
                }
        }
        .defaultSize(width: 1200, height: 850)
        .commands {
            CommandMenu("Navigate") {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element.id) { index, section in
                    Button(section.rawValue) {
                        navigate?(section)
                    }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command).disabled(navigate == nil)
                }
            }
            CommandGroup(after: .newItem) {
                Button("Sync Library") { Task { await store.refreshAccountTheme(); try? await store.refreshList() } }.keyboardShortcut("r")
            }
        }
        Settings {
            NavigationStack { AccountView() }.environment(store)
                .environment(\.accountTheme, store.user?.accountTheme ?? AccountTheme())
                .tint((store.user?.accountTheme ?? AccountTheme()).accent)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
                .frame(width: 620, height: 720)
                .task { await store.refreshAccountTheme() }
        }
    }
}
struct AsunaNavigationKey: FocusedValueKey { typealias Value = (AppSection) -> Void }
extension FocusedValues {
    var asunaNavigation: AsunaNavigationKey.Value? {
        get { self[AsunaNavigationKey.self] }
        set { self[AsunaNavigationKey.self] = newValue }
    }
}
#endif

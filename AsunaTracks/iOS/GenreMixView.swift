import SwiftUI

struct GenreMixView: View {
    @Environment(\.accountTheme) private var theme
    @Namespace private var mixNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var genres: [Genre] = []
    @State private var selected: Set<Int> = []
    @State private var query = ""
    @State private var items: [Media] = []
    @State private var loading = false
    @State private var error: String?
    @State private var searched = false
    @State private var page = 1
    @State private var more = false
    @State private var requestID = UUID()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Pick a mood").font(.largeTitle.bold())
                Text("Mix up to six genres and themes. Every result matches every choice.").foregroundStyle(.secondary)
                HStack {
                    Text("Your mix · \(selected.count)/6").font(.headline)
                    Spacer()
                    Button("Clear") { selected.removeAll(); reset() }.disabled(selected.isEmpty || loading)
                }
                if !selected.isEmpty {
                    ScrollView(.horizontal) {
                        GlassEffectContainer(spacing: 10) {
                            HStack(spacing: 10) {
                                ForEach(genres.filter { selected.contains($0.id) }) { genre in
                                    Button { withAnimation(reduceMotion ? nil : .smooth) { selected.remove(genre.id); reset() } } label: {
                                        Label(genre.name, systemImage: "xmark").font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 12)
                                    }.buttonStyle(.plain)
                                        .glassEffect(.regular.tint(theme.accent.opacity(0.3)).interactive(), in: Capsule())
                                        .glassEffectID(genre.id, in: mixNamespace)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
                TextField("Find a genre or theme", text: $query).textFieldStyle(.roundedBorder).accessibilityLabel("Search genres")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(genres.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { genre in
                        Button {
                            withAnimation(reduceMotion ? nil : .smooth) {
                                if selected.contains(genre.id) { selected.remove(genre.id) } else { selected.insert(genre.id) }
                                reset()
                            }
                        } label: {
                            HStack { Text(genre.name); Spacer(minLength: 0); if selected.contains(genre.id) { Image(systemName: "checkmark") } }.frame(minHeight: 30)
                        }.buttonStyle(.bordered).tint(selected.contains(genre.id) ? theme.accent : .secondary)
                            .disabled(loading || (!selected.contains(genre.id) && selected.count >= 6))
                            .accessibilityAddTraits(selected.contains(genre.id) ? .isSelected : [])
                    }
                }
                if loading { AsunaLoadingView(title: "Finding your mix…", accent: theme.accent) }
                if let error { Text(error).foregroundStyle(.red); Button("Try again") { Task { if genres.isEmpty { await loadGenres() } else { await find(reset: true) } } } }
                if searched && !loading && items.isEmpty && error == nil { ContentUnavailableView("No exact matches", systemImage: "slider.horizontal.3", description: Text("Remove a genre to broaden your mix.")) }
                MediaGrid(items: items)
                if more { Button("Load more") { Task { await find(reset: false) } }.buttonStyle(.glass).disabled(loading) }
            }.padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.asunaSurface()
        .safeAreaInset(edge: .bottom) {
            Button { Task { await find(reset: true) } } label: {
                Label(loading ? "Finding your mix…" : "Find my next anime", systemImage: "sparkles")
                    .font(.headline).padding(.horizontal, 20).padding(.vertical, 10)
            }.buttonStyle(.glassProminent).disabled(selected.isEmpty || loading).padding(16)
        }
        .navigationTitle("Genre mix").navigationBarTitleDisplayMode(.inline).task { await loadGenres() }
    }
    private func reset() { requestID = UUID(); items = []; searched = false; more = false; error = nil }
    private func loadGenres() async {
        do { let response: GenreResponse = try await APIClient.shared.request("api/genres", query: ["type": "anime"]); genres = response.genres.filter { $0.kind != "explicit" }.sorted { $0.name < $1.name }; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func find(reset: Bool) async {
        loading = true; error = nil
        let id = UUID(); requestID = id
        let next = reset ? 1 : page + 1
        defer { loading = false }
        do {
            let response: MediaPage = try await APIClient.shared.request("api/discover/mood", query: ["genres": selected.sorted().map(String.init).joined(separator: ","), "page": String(next)])
            guard id == requestID else { return }
            items = reset ? response.items : items + response.items.filter { new in !items.contains { $0.identity == new.identity } }
            searched = true; page = next; more = response.pagination?.hasNextPage ?? false
        } catch { if id == requestID { self.error = error.localizedDescription } }
    }
}

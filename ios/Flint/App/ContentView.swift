import SwiftUI

struct ContentView: View {
    // T0 scaffold: an empty shell. The vault navigator (T1) and the
    // CodeMirror editor (T3) will replace this. See docs/TASKS.md.
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Flint")
                .font(.largeTitle.bold())
            Text("Scaffold — Phase 1a starts here.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

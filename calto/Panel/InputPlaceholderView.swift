import SwiftUI

struct InputPlaceholderView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Paste a screenshot or text", systemImage: "doc.on.clipboard")
        } description: {
            Text("Input arrives in the next stage.")
        }
        .frame(minWidth: 420, minHeight: 260)
    }
}

#Preview {
    InputPlaceholderView()
}

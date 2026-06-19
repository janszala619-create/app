import SwiftUI

struct CaptureButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 82, height: 82)
                    .shadow(color: Color.pink.opacity(0.32), radius: 24, y: 10)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.52, green: 0.30, blue: 1.0),
                                Color(red: 1.0, green: 0.23, blue: 0.58),
                                Color(red: 1.0, green: 0.43, blue: 0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 68, height: 68)

                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 88, height: 88)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Neue Erinnerung oder Notiz erfassen")
        .accessibilityHint("Öffnet die Erfassung")
    }
}

private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

#Preview {
    CaptureButton {}
        .padding()
}

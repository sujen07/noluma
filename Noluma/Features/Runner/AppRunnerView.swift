import SwiftUI
import WebKit

private struct SandboxedAppView: UIViewRepresentable {
    let controller: SandboxController

    func makeUIView(context: Context) -> WKWebView {
        controller.load()
        return controller.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

/// Runs one mini-app full screen inside the offline sandbox.
struct AppRunnerView: View {
    let app: MiniApp

    @Environment(AppLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var controller: SandboxController?
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if let controller {
                    SandboxedAppView(controller: controller)
                        .ignoresSafeArea(.container, edges: .bottom)
                } else if let failure {
                    ContentUnavailableView("Couldn't open this app", systemImage: "exclamationmark.triangle", description: Text(failure))
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        .task { await start() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppIconView(icon: app.icon, tint: app.tint, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Label("Offline · data stays on this iPhone", systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close app")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func start() async {
        guard controller == nil else { return }
        guard library.html(for: app.id) != nil else {
            failure = "Its files are missing from this device."
            return
        }
        do {
            let rules = try await SandboxPolicy.ruleList()
            let id = app.id
            controller = SandboxController(appID: id, ruleList: rules) { [library] in
                MainActor.assumeIsolated { library.html(for: id) }
            }
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct AppIconView: View {
    let icon: String
    let tint: String
    var size: CGFloat = 60

    var body: some View {
        let color = AppTint.color(tint)
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: AppSymbol.normalized(icon))
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

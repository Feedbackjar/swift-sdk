#if canImport(SwiftUI)
import SwiftUI

/// The "New feedback" screen: multiline editor, optional name/email per config,
/// a primary Send button.
struct FJNewFeedback: View {
    let config: WidgetConfig
    var onDone: () -> Void
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.fjAccent) private var accent

    @State private var text = ""
    @State private var name = ""
    @State private var email = ""
    @State private var sending = false
    @State private var error = ""
    @State private var prefilled = false

    var body: some View {
        let palette = fjPalette(scheme, accent)
        let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Cancel", action: onCancel)
                        .font(.system(size: FJFont.body))
                        .foregroundColor(palette.textDim)
                        .buttonStyle(.plain)
                    Spacer()
                    Text("New feedback")
                        .font(.system(size: FJFont.body, weight: .bold))
                        .foregroundColor(palette.text)
                    Spacer()
                    Color.clear.frame(width: 52, height: 1)
                }
                .padding(.bottom, 8)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Share your feedback…")
                            .font(.system(size: FJFont.body))
                            .foregroundColor(palette.textDim)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: FJFont.body))
                        .foregroundColor(palette.text)
                        .modifier(FJClearEditorBackground())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(minHeight: 120)
                }
                .background(RoundedRectangle(cornerRadius: fjRadius).fill(palette.field))

                if config.collectName {
                    field("Name", text: $name, palette: palette)
                }
                if config.collectEmail {
                    field("Email", text: $email, palette: palette)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                if !error.isEmpty {
                    Text(error)
                        .font(.system(size: FJFont.small))
                        .foregroundColor(palette.accent)
                }

                Button(action: send) {
                    Group {
                        if sending {
                            ProgressView().tint(.white)
                        } else {
                            Text("Send").font(.system(size: FJFont.body, weight: .bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundColor(.white)
                    .background(RoundedRectangle(cornerRadius: fjRadius).fill(palette.accent))
                    .opacity(canSend ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .padding(.top, 4)
            }
            .padding(20)
        }
        .background(palette.bg.ignoresSafeArea())
        .task {
            guard !prefilled else { return }
            prefilled = true
            let identity = FeedbackJar.shared.getIdentity()
            if let n = identity.name, name.isEmpty { name = n }
            if let e = identity.email, email.isEmpty { email = e }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, palette: FJPalette) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: FJFont.body))
            .foregroundColor(palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: fjRadius).fill(palette.field))
    }

    @MainActor
    private func send() {
        guard let content = fjTrimmedOrNil(text), !sending else { return }
        sending = true
        error = ""
        // `submit` persists name/email via `setIdentity` automatically.
        let submittedName = config.collectName ? fjTrimmedOrNil(name) : nil
        let submittedEmail = config.collectEmail ? fjTrimmedOrNil(email) : nil

        Task { @MainActor in
            let result = await FeedbackJar.shared.submit(
                content,
                email: submittedEmail,
                name: submittedName
            )
            sending = false
            switch result {
            case .success:
                onDone()
            case .failure(let err):
                error = fjMessage(err)
            }
        }
    }
}
#endif

import MessageUI
import SwiftUI
import UIKit

// MARK: - Feedback submission (HTTPS; in-app text only)

/// [Web3Forms](https://web3forms.com) JSON `POST` for quick text feedback. For attachments or longer detail,
/// users can use **Email with Mail** (opens the system mail app).
private enum FeedbackSubmissionConfig {
    static let web3formsAccessKey = "ddb55faf-1c91-4f03-8753-e014e9c27f7e"
    static let messageSubject = "FluxCut Feedback"
    private static let submitURL = URL(string: "https://api.web3forms.com/submit")!

    static func makeFeedbackRequest(kind: FeedbackKind, composedBody: String) throws -> URLRequest {
        let key = web3formsAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw FeedbackSubmitError.missingAccessKey
        }
        var request = URLRequest(url: submitURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let payload: [String: Any] = [
            "access_key": key,
            "subject": "\(messageSubject) — \(kind.rawValue)",
            "message": composedBody,
            "from_name": "FluxCut iOS",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }
}

private enum SupportEmailConfig {
    static let address = "fluxcut.support@gmail.com"
}

private enum FeedbackSubmitError: LocalizedError {
    case missingAccessKey

    var errorDescription: String? {
        switch self {
        case .missingAccessKey:
            return "Add your Web3Forms access key in FeedbackSubmissionConfig (see SettingsSupportViews.swift), or create one at web3forms.com."
        }
    }
}

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.title2.weight(.bold))

                policySection(
                    title: "1. Introduction",
                    text: """
                    FluxCut (“we,” “our,” or “the app”) respects your privacy. This Privacy Policy describes how information is handled when you use the FluxCut mobile application on Apple devices. By using FluxCut, you agree to this policy. If you do not agree, please discontinue use of the app.
                    """
                )

                policySection(
                    title: "2. Local Processing",
                    text: """
                    FluxCut is designed to create videos from content you provide—such as scripts, narration, photos, videos, and music—on your device. Core editing, preview generation, and export operations run locally on your iPhone or iPad. We do not operate FluxCut as a cloud editing service; your projects are not uploaded to our servers by the app itself for routine editing.
                    """
                )

                policySection(
                    title: "3. Information You Provide",
                    text: """
                    You may enter or import text, media, and audio into FluxCut. This content remains under your control and is stored in your app’s sandbox and related local storage on your device unless you choose to share exported files or use system features (for example, sharing to another app) outside FluxCut.
                    """
                )

                policySection(
                    title: "4. Photos, Media, and Microphone",
                    text: """
                    FluxCut may request access to your photo library or files so you can import images and videos. Access is used only to let you select and work with the assets you choose. The app does not use the microphone unless a future feature explicitly requests it and you grant permission; the current feature set is focused on imported and generated media as described in the app.
                    """
                )

                policySection(
                    title: "5. Speech and Voices",
                    text: """
                    Narration playback and export may use Apple’s text-to-speech and system voices you have enabled on your device. Those services are subject to Apple’s terms and privacy practices. FluxCut does not send your script to our servers for voice synthesis; processing occurs through Apple’s on-device or system frameworks as applicable.
                    """
                )

                policySection(
                    title: "6. Purchases",
                    text: """
                    Optional purchases or entitlements may be offered through the App Store. Apple processes payment and provides us only the information necessary to validate entitlements (for example, transaction status). We do not receive your full payment card details.
                    """
                )

                policySection(
                    title: "7. Analytics and Crash Data",
                    text: """
                    Unless separately disclosed in a future app update, FluxCut does not embed third-party advertising SDKs for cross-app tracking. If crash reporting or minimal analytics are added later, this policy will be updated and, where required, additional consent will be requested.
                    """
                )

                policySection(
                    title: "8. Data Retention and Deletion",
                    text: """
                    Project data, previews, and caches reside on your device. You can remove unused data and current project data from Storage in Settings. Uninstalling the app removes its sandbox data from the device subject to Apple’s system behavior.
                    """
                )

                policySection(
                    title: "9. Children’s Privacy",
                    text: """
                    FluxCut is not directed at children under the age required by applicable law to obtain parental consent for data collection. If you believe we have inadvertently collected information from a child, please contact us so we can take appropriate steps.
                    """
                )

                policySection(
                    title: "10. International Users",
                    text: """
                    If you use FluxCut from outside your home country, your information may be processed on your device in accordance with this policy and applicable local laws.
                    """
                )

                policySection(
                    title: "11. Changes to This Policy",
                    text: """
                    We may update this Privacy Policy from time to time. The updated version will be made available within the app or through other reasonable notice. Continued use after changes constitutes acceptance of the revised policy.
                    """
                )

                policySection(
                    title: "12. Contact",
                    text: """
                    For privacy-related questions, you may contact us through the Feedback option in Settings. We will respond in line with applicable law.
                    """
                )

                Text("Last updated: April 2026")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func policySection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Feedback

enum FeedbackKind: String, CaseIterable, Identifiable {
    case general = "General feedback"
    case bug = "Bug report"
    case suggestion = "Suggestion"

    var id: String { rawValue }
}

struct FeedbackSubmissionView: View {
    @State private var kind: FeedbackKind = .general
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var showSubmitSuccess = false
    @State private var showSubmitError = false
    @State private var submitErrorMessage = ""
    @State private var showCopiedConfirmation = false
    @State private var showMailOpenFailed = false
    @State private var showInAppMailComposer = false

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedMessage.isEmpty
    }

    private var appVersionLine: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    private var osVersionLine: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    private func composedBody() -> String {
        let textBlock = trimmedMessage.isEmpty ? "(No text)" : trimmedMessage
        return """
        Type: \(kind.rawValue)

        \(textBlock)

        ---
        App version: \(appVersionLine)
        OS: \(osVersionLine)
        """
    }

    /// Prefills the Mail app draft (user can attach photos/videos there).
    private func supportMailBody() -> String {
        let note = trimmedMessage.isEmpty ? "(Add your message here.)" : trimmedMessage
        return """
        Type: \(kind.rawValue)

        \(note)

        ---
        App version: \(appVersionLine)
        OS: \(osVersionLine)
        """
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Send quick text feedback below—it’s delivered over a secure connection without opening Mail.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Type", selection: $kind) {
                    ForEach(FeedbackKind.allCases) { k in
                        Text(k.rawValue).tag(k)
                    }
                }
                .pickerStyle(.segmented)

                Text("Message")
                    .font(.subheadline.weight(.semibold))

                TextEditor(text: $message)
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                Button {
                    Task { await submitTapped() }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isSubmitting ? "Sending…" : "Submit")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || isSubmitting)
                .opacity(canSubmit && !isSubmitting ? 1 : 0.45)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Need to send more?")
                        .font(.subheadline.weight(.semibold))
                    Text(
                        "Opens your default email app (Mail, Gmail, or another app you chose in Settings). If nothing opens, you can compose email inside FluxCut when an account is set up. Your draft includes what you typed above."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Button {
                        openSupportInMailApp()
                    } label: {
                        Label("Email support in Mail", systemImage: "envelope.open.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Thanks", isPresented: $showSubmitSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your feedback was sent.")
        }
        .alert("Couldn’t send", isPresented: $showSubmitError) {
            Button("Copy message") {
                UIPasteboard.general.string = composedBody()
                showCopiedConfirmation = true
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(submitErrorMessage)
        }
        .alert("Copied", isPresented: $showCopiedConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your feedback was copied to the clipboard.")
        }
        .alert("Mail wasn’t opened", isPresented: $showMailOpenFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add a mail account in Settings → Mail, or copy the address \(SupportEmailConfig.address) and send from another device or app.")
        }
        .sheet(isPresented: $showInAppMailComposer) {
            SupportMailComposeView(
                isPresented: $showInAppMailComposer,
                recipients: [SupportEmailConfig.address],
                subject: "\(FeedbackSubmissionConfig.messageSubject) — \(kind.rawValue)",
                messageBody: supportMailBody()
            )
        }
    }

    private func openSupportInMailApp() {
        let subject = "\(FeedbackSubmissionConfig.messageSubject) — \(kind.rawValue)"
        guard var components = URLComponents(string: "mailto:\(SupportEmailConfig.address)") else {
            showMailOpenFailed = true
            return
        }
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: supportMailBody()),
        ]
        guard let url = components.url else {
            showMailOpenFailed = true
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            Task { @MainActor in
                if success { return }
                // No app handled mailto (e.g. default mail app removed, or no handler). Use system in-app composer if possible.
                if MFMailComposeViewController.canSendMail() {
                    showInAppMailComposer = true
                } else {
                    showMailOpenFailed = true
                }
            }
        }
    }

    private func submitTapped() async {
        guard canSubmit else { return }

        let request: URLRequest
        do {
            request = try FeedbackSubmissionConfig.makeFeedbackRequest(
                kind: kind,
                composedBody: composedBody()
            )
        } catch {
            await MainActor.run {
                submitErrorMessage = error.localizedDescription
                showSubmitError = true
            }
            return
        }

        await MainActor.run { isSubmitting = true }
        defer {
            Task { @MainActor in
                isSubmitting = false
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await MainActor.run {
                    submitErrorMessage = "Unexpected response from the server."
                    showSubmitError = true
                }
                return
            }

            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let successFlag = json?["success"] as? Bool

            if http.statusCode == 200, successFlag == true {
                await MainActor.run {
                    message = ""
                    showSubmitSuccess = true
                }
                return
            }

            let serverMessage = feedbackErrorMessage(from: json, httpStatus: http.statusCode, rawData: data)
            await MainActor.run {
                submitErrorMessage = serverMessage
                showSubmitError = true
            }
        } catch {
            await MainActor.run {
                submitErrorMessage =
                    "\(error.localizedDescription) You can copy your message and try again when you’re online."
                showSubmitError = true
            }
        }
    }

    private func feedbackErrorMessage(from json: [String: Any]?, httpStatus: Int, rawData: Data) -> String {
        if let json {
            if let body = json["body"] as? [String: Any], let msg = body["message"] as? String, !msg.isEmpty {
                return web3FormsUserFacingMessage(msg, httpStatus: httpStatus)
            }
            if let msg = json["message"] as? String, !msg.isEmpty {
                return web3FormsUserFacingMessage(msg, httpStatus: httpStatus)
            }
        }
        if httpStatus == 413 {
            return "The message was too large for the server. Try a shorter note."
        }
        if httpStatus == 400, rawData.count < 1200,
           let text = String(data: rawData, encoding: .utf8),
           text.localizedCaseInsensitiveContains("request")
        {
            return "The server couldn’t accept this message. Try a shorter note."
        }
        if let text = String(data: rawData, encoding: .utf8), text.count < 500, !text.isEmpty {
            return "Server response (\(httpStatus)): \(text)"
        }
        return "Couldn’t send feedback (code \(httpStatus)). You can copy your message and try again."
    }

    private func web3FormsUserFacingMessage(_ serverMessage: String, httpStatus: Int) -> String {
        if serverMessage.localizedCaseInsensitiveContains("too long")
            || serverMessage.localizedCaseInsensitiveContains("request too long")
        {
            return "The message was too large for the server. Try a shorter note."
        }
        if httpStatus == 400 {
            return "\(serverMessage) Try a shorter message."
        }
        return serverMessage
    }
}

// MARK: - In-app mail (fallback when mailto: cannot open an external app)

private struct SupportMailComposeView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let recipients: [String]
    let subject: String
    let messageBody: String

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients(recipients)
        mail.setSubject(subject)
        mail.setMessageBody(messageBody, isHTML: false)
        return mail
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        @Binding var isPresented: Bool

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            isPresented = false
        }
    }
}

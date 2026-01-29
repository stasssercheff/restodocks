//
//  TechnologyTranslationView.swift
//  Restodocks
//
//  Перевод технологии приготовления на другой язык (Apple Translation, on-device).
//

import SwiftUI
import Translation

struct TechnologyTranslationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var lang: LocalizationManager

    let sourceText: String
    let sourceLang: String
    let targetLang: String
    let onComplete: (String) -> Void
    var onCancel: (() -> Void)?

    @State private var config: TranslationSession.Configuration?
    @State private var errorMessage: String?
    @State private var isTranslating = true

    private var targetLanguageName: String {
        let key = "lang_\(targetLang)"
        return (lang.t(key) != key) ? lang.t(key) : targetLang.uppercased()
    }

    var body: some View {
        NavigationStack {
            Group {
                if let err = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(err)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if isTranslating {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("\(lang.t("translating")) \(targetLanguageName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(lang.t("translate_technology"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.t("cancel")) {
                        onCancel?()
                        dismiss()
                    }
                }
            }
            .translationTask(config) { session in
                await runTranslation(session: session)
            }
        }
        .onAppear {
            guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                isTranslating = false
                errorMessage = lang.t("translation_empty_source")
                return
            }
            config = TranslationSession.Configuration(
                source: Locale.Language(identifier: sourceLang),
                target: Locale.Language(identifier: targetLang)
            )
        }
    }

    private func runTranslation(session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
            let response = try await session.translate(sourceText)
            await MainActor.run {
                isTranslating = false
                config = nil
                onComplete(response.targetText)
                dismiss()
            }
        } catch {
            await MainActor.run {
                isTranslating = false
                config = nil
                errorMessage = error.localizedDescription
            }
        }
    }
}

import SwiftUI
import Supabase
import PostgREST

struct TestConnectionView: View {

    @EnvironmentObject var lang: LocalizationManager
    @State private var resultText = ""

    var body: some View {
        VStack(spacing: 20) {

            Text(resultText.isEmpty ? lang.t("press_to_test") : resultText)
                .padding()
                .multilineTextAlignment(.center)

            Button(lang.t("test_connection")) {
                testSupabaseConnection()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding()
    }

    // MARK: - Test Supabase connection
    func testSupabaseConnection() {
        Task {
            do {
                let data: [Review] = try await SupabaseManager.shared.client
                    .from("reviews")
                    .select()
                    .limit(1)
                    .execute()
                    .value

                await MainActor.run {
                    resultText = lang.t("connection_success") + " \(data.count)"
                }

            } catch {
                await MainActor.run {
                    resultText = lang.t("connection_error") + " \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Review model (обязательно!)
struct Review: Codable {
    let id: Int?
    let user_id: String?
    let text: String?
    let rating: Int?
    let created_at: String?
}

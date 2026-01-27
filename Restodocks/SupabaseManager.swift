import Foundation
import Supabase

final class SupabaseManager {

    static let shared = SupabaseManager()

    private let supabaseUrl = URL(string: "https://osglfptwbuqqmqunttha.supabase.co")!
    private let supabaseKey = "sb_publishable_VLi05Njkuzk_SBkLB_8j0A_00jr73Im"

    let client: SupabaseClient

    private init() {
        // Минимальная надёжная и рабочая инициализация — используем её, она у тебя уже работала.
        self.client = SupabaseClient(
            supabaseURL: supabaseUrl,
            supabaseKey: supabaseKey
        )
        print("🔥 SupabaseManager initialized")
    }
}

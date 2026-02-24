import Foundation
import Supabase

final class SupabaseManager {

    static let shared = SupabaseManager()

    private let supabaseUrl = URL(string: "https://osglfptwbuqqmqunttha.supabase.co")!
    private let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE"

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

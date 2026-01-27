struct PrepView: View {
    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        List {
            NavigationLink { PrepMenuView() } label: { Text(lang.t("menu")) }
            NavigationLink { PrepTTKView() } label: { Text(lang.t("ttk")) }
            NavigationLink { PrepScheduleView() } label: { Text(lang.t("schedule")) }
        }
        .navigationTitle(lang.t("prep"))
    }
}
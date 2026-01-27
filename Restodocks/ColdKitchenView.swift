struct ColdKitchenView: View {
    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        List {
            NavigationLink { ColdKitchenMenuView() } label: { Text(lang.t("menu")) }
            NavigationLink { ColdKitchenTTKView() } label: { Text(lang.t("ttk")) }
            NavigationLink { ColdKitchenScheduleView() } label: { Text(lang.t("schedule")) }
        }
        .navigationTitle(lang.t("cold_kitchen"))
    }
}
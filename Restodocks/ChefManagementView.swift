import SwiftUI

struct ChefManagementView: View {

    var body: some View {
        List {

            NavigationLink {
                HotKitchenScheduleView()
            } label: {
                Text("Hot Kitchen Schedule")
            }

            NavigationLink {
                ColdKitchenScheduleView()
            } label: {
                Text("Cold Kitchen Schedule")
            }

        }
        .navigationTitle("Head Chef")
    }
}

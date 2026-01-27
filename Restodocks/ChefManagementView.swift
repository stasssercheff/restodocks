import SwiftUI

struct ChefManagementView: View {

    var body: some View {
        List {
            NavigationLink {
                ChefAddShiftView()
            } label: {
                Text("Edit Kitchen Schedule")
            }

            NavigationLink {
                KitchenScheduleView()
            } label: {
                Text("Kitchen Schedule")
            }
        }
        .navigationTitle("Head Chef")
    }
}
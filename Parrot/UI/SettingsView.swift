import SwiftUI

/// Parrot's settings: the popover's model and hands-free controls, meeting reminders, and
/// managing downloaded models.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                VStack(alignment: .leading, spacing: 12) {
                    EnginePicker()
                    HandsFreeTile()
                    MeetingsTile()
                    Spacer(minLength: 0)
                }
                .padding(20)
                .frame(width: 420)
            }
            Tab("Models", systemImage: "square.and.arrow.down") {
                ModelsView()
                    .frame(width: 560, height: 440)
            }
        }
    }
}

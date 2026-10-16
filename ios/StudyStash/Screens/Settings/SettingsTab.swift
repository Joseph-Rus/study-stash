import SwiftUI

/// Which library this is, this phone, and removing it.
struct SettingsTab: View {
    @Environment(AppModel.self) private var app
    @State private var me: Me?
    @State private var confirming = false
    @State private var reminderTick = 0

    private func reschedule() {
        reminderTick += 1
        Task { await app.refreshInBackground() }
    }

    var body: some View {
        // Pushed from Home's toolbar (Route.settings), inside Home's stack.
        Group {
            Form {
                Section("Library") {
                    LabeledContent {
                        Text(app.offline ? "Offline" : "Connected").foregroundStyle(app.offline ? .orange : .green)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(me?.library.name ?? app.libraryName).font(.headline)
                            if let v = me?.library.version { Text("Study Stash \(v)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if let base = app.api?.base {
                        LabeledContent("Address", value: base.host() ?? base.absoluteString).font(.subheadline)
                    }
                }

                Section {
                    NavigationLink {
                        UsesView()
                    } label: {
                        LabeledContent("Used for", value: (app.uses ?? []).isEmpty ? "School" : (app.uses ?? []).map { u in UsesView.kinds.first { $0.id == u }?.title ?? u }.joined(separator: ", "))
                    }
                }

                Section {
                    Toggle("When a class starts, offer to record", isOn: Binding(get: { Reminders.Settings.classStart }, set: { Reminders.Settings.classStart = $0; reschedule() }))
                    Toggle("Work due: the evening before and 2 hours before", isOn: Binding(get: { Reminders.Settings.due }, set: { Reminders.Settings.due = $0; reschedule() }))
                    Toggle("Notes ready for a lecture recorded here", isOn: Binding(get: { Reminders.Settings.notes }, set: { Reminders.Settings.notes = $0 }))
                } header: {
                    Text("Notifications")
                }

                Section {
                    LabeledContent("Name", value: me?.device?.name ?? UIDevice.current.name)
                    if let added = me?.device?.added, let d = Format.parse(added) {
                        LabeledContent("Added", value: Format.shortDate(d))
                    }
                    if app.isDemo {
                        Button("Leave the demo") { Task { await app.forget() } }
                    } else {
                        Button("Remove this phone", role: .destructive) { confirming = true }
                    }
                } header: {
                    Text("This phone")
                } footer: {
                    Text("This phone reads your library until it's removed, here or in Study Stash's Settings → Phone on your computer.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                }
            }
            .scrollContentBackground(.hidden)
            .background(.surface)
            .navigationTitle("Settings")
            .task { me = try? await app.api?.me() }
            .id(reminderTick)
            .confirmationDialog("Remove this phone from \(app.libraryName)?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { Task { await app.forget() } }
            } message: {
                Text("To use it again, add it from Study Stash's Settings → Phone on your computer.")
            }
        }
    }
}

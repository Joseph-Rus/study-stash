import SwiftUI

// Chats, as the desktop's Chats list has them (AiChatsMenu): the conversations kept where Ask was opened, newest
// first, each named for its first question, with when it was last added to and what it's about. One picked opens to
// carry on; New chat starts another; a swipe deletes one (on the computer too), with Undo. The Ask tab lists them
// all, the computer's included; a class's Ask its own and its lectures'; a lecture's its own.

/// A kept chat in a list: its first question, then "Yesterday 8:40 PM · Organic Chemistry".
struct ChatRow: View {
    var chat: ChatSummary
    /// What it's about, where the list holds more than one place's ("Organic Chemistry", a lecture's title).
    var about: String
    var current = false
    var opening = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(chat.title.isEmpty ? "Chat" : chat.title).textStyle(.nav).fontWeight(current ? .bold : .medium)
                        .foregroundStyle(.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(sub).textStyle(.meta).foregroundStyle(.inkSubtle).lineLimit(1)
                }
                Spacer(minLength: 8)
                if opening {
                    StudyLoader(.inline, color: .inkSubtle)
                } else if current {
                    Icon("check", size: 16).foregroundStyle(.ink)
                } else {
                    Icon("chevron_right", size: 16).foregroundStyle(.inkSubtle)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.row)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(current ? [.isSelected] : [])
        .accessibilityHint("Opens the chat to carry on")
        .accessibilityIdentifier("ask.chat")
    }

    private var sub: String {
        let when = Format.parse(chat.updated).map { Format.chatWhen($0) } ?? ""
        return [when, about].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The chats kept where Ask was opened, in a sheet over it.
struct ChatsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var place: AskPlace
    /// The chat open in Ask now.
    var current: String?
    /// Chats started on this phone that the library's list may not have yet (over Google Drive, its copy follows).
    var made: [ChatSummary] = []
    var recent: [LectureSummary]
    var overDrive: Bool
    var onOpen: (Chat) -> Void
    var onNew: () -> Void
    var onDeleted: (String) -> Void

    @State private var chats: [ChatSummary]?
    @State private var problem: String?
    @State private var opening: String?
    /// The chat just deleted, while Undo can bring it back.
    @State private var deleted: ChatSummary?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Undo, at the top under the bar (a sheet at half height has its foot out of sight).
                if let d = deleted {
                    HStack(spacing: 14) {
                        Text("Chat deleted.").font(.atkinson(14.5, .medium, relativeTo: .subheadline)).foregroundStyle(.ink)
                        Button("Undo") { Task { await restore(d) } }
                            .buttonStyle(.textLink)
                            .accessibilityIdentifier("chats.undo")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(.surface, in: .rect(cornerRadius: Radius.panel))
                    .lifted(.float, in: RoundedRectangle(cornerRadius: Radius.panel))
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: d.id) {
                        try? await Task.sleep(for: .seconds(6))
                        withAnimation { if deleted?.id == d.id { deleted = nil } }
                    }
                }
                Group {
                    if let chats, !chats.isEmpty {
                        list(chats)
                    } else if chats != nil {
                        ScrollView {
                            EmptyText("No chats yet. Each conversation you start in Ask is kept here, and on your computer too.")
                                .padding(.horizontal, Space.pageCompact)
                                .padding(.top, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if let problem {
                        ScrollView {
                            EmptyState(title: overDrive ? "Can't reach your laptop" : "Can't reach your library", detail: problem, actionTitle: "Try again") {
                                Task { await load() }
                            }
                            .padding(.horizontal, Space.pageCompact)
                        }
                    } else {
                        StudyLoader(.screen, color: .inkSubtle).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .page()
            .foregroundStyle(.ink)
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onNew()
                        dismiss()
                    } label: { Label("New chat", icon: "edit_square") }
                    .accessibilityIdentifier("chats.new")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("Done").textStyle(.button) }
                }
            }
            .animation(.smooth, value: deleted?.id)
            .toast($toast)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    private func list(_ chats: [ChatSummary]) -> some View {
        List {
            ForEach(chats) { c in
                ChatRow(chat: c, about: Self.whereWords(c, at: place, recent: recent), current: c.id == current, opening: opening == c.id) {
                    Task { await open(c) }
                }
                .listRowBackground(Color.surface)
                .listRowSeparatorTint(.line)
                .listRowInsets(EdgeInsets(top: 0, leading: Space.pageCompact, bottom: 0, trailing: Space.pageCompact))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { Task { await delete(c) } } label: { Label("Delete", icon: "delete") }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func load() async {
        guard let api = app.api else { return }
        do {
            let all = try await api.askChats()
            chats = Self.kept(all + made.filter { m in !all.contains { $0.id == m.id } }, at: place)
            problem = nil
            #if DEBUG
            // `-ask-undo`: the newest deleted, for a picture of Undo.
            if DebugLaunch.flag("-ask-undo"), deleted == nil, let first = chats?.first { await delete(first) }
            #endif
        } catch {
            if chats == nil { problem = (error as? APIError)?.detail ?? "Your chats couldn't be loaded." }
        }
    }

    private func open(_ c: ChatSummary) async {
        guard let api = app.api, opening == nil else { return }
        opening = c.id
        defer { opening = nil }
        do {
            let chat = try await api.chat(c.id)
            onOpen(chat)
            dismiss()
        } catch {
            toast = (error as? APIError)?.detail ?? "That chat couldn't be opened."
        }
    }

    /// Deleted at once, with Undo for a few seconds (the library keeps a deleted chat a day).
    private func delete(_ c: ChatSummary) async {
        guard let api = app.api else { return }
        // Out of the list at once: over Google Drive the laptop deletes it when it next looks.
        withAnimation { chats?.removeAll { $0.id == c.id } }
        deleted = c
        onDeleted(c.id)
        do {
            try await api.deleteChat(c.id)
        } catch let e as APIError where e.status == 404 {
            // Gone already.
        } catch {
            if !overDrive {
                deleted = nil
                toast = (error as? APIError)?.detail ?? "That chat couldn't be deleted."
            }
        }
    }

    /// Undo: the chat back in the list at once, and in the library (over Google Drive, when the laptop next looks).
    /// A library that can't (an older one, or a day gone) says so, and it leaves the list again.
    private func restore(_ c: ChatSummary) async {
        guard let api = app.api else { return }
        withAnimation {
            deleted = nil
            if chats?.contains(where: { $0.id == c.id }) == false { chats = Self.kept((chats ?? []) + [c], at: place) }
        }
        do {
            try await api.restoreChat(c.id)
        } catch let e as APIError where [403, 404, 405].contains(e.status) {
            withAnimation { chats?.removeAll { $0.id == c.id } }
            toast = "That chat couldn't come back."
        } catch {
            // Not answered yet: over Google Drive it waits in the phone's box until the laptop does it.
        }
    }

    /// The Ask chats kept at `place`, newest first: all of them for Home (the Ask tab), a class's own and its
    /// lectures', or one lecture's.
    static func kept(_ all: [ChatSummary], at place: AskPlace) -> [ChatSummary] {
        let here = all.filter { c in
            switch place.scope {
            case "lecture": c.lecture == place.lecture
            case "class": c.class == place.class
            default: true
            }
        }
        return here.sorted { (Format.parse($0.updated) ?? .distantPast) > (Format.parse($1.updated) ?? .distantPast) }
    }

    /// What a chat is about, where the list holds more than one place's: a lecture's title (or its class), a class.
    static func whereWords(_ c: ChatSummary, at place: AskPlace, recent: [LectureSummary]) -> String {
        if place.scope == "lecture" { return "" }
        if c.scope == "lecture" || (c.scope == nil && !c.lecture.isEmpty) {
            let title = recent.first { $0.id == c.lecture }?.title
                ?? ResponseCache.shared.read("lecture:\(c.lecture)", as: Lecture.self)?.title
            if let title, !title.isEmpty { return title }
            return place.scope == "class" ? "" : c.class
        }
        return place.scope == "home" ? c.class : ""
    }
}

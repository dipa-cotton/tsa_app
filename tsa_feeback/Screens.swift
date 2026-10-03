import SwiftUI
import PhotosUI
import Photos

// MARK: - Theme (tweak colors/fonts here)
extension Color {
    init(hex: UInt) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
enum Theme {
    static let ink = Color(hex: 0x4A9EE6)     // text + primary button
    static let pill = Color(hex: 0xA4CBEC)    // light blue pills
    static let field = Color(hex: 0xF3EFEF)   // off-white pills / inputs
    static let paper = Color(hex: 0xF7F1F4)
    static let grid = Color(hex: 0x8CC8FA)
    static func font(_ s: CGFloat, bold: Bool = false) -> Font { .custom(bold ? "Baskerville-Bold" : "Baskerville", size: s) }
}

struct GridBackground: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path(); let step: CGFloat = 20
            for x in stride(from: 0, through: size.width, by: step) { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }
            for y in stride(from: 0, through: size.height, by: step) { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }
            ctx.stroke(p, with: .color(Theme.grid.opacity(0.6)), lineWidth: 1.2)
        }
        .background(Theme.paper).ignoresSafeArea()
    }
}

struct Pill: View {
    let text: String
    var fill = Theme.pill, fg = Theme.ink
    var size: CGFloat = 26
    var body: some View {
        Text(text).font(Theme.font(size)).foregroundColor(fg).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 12)
            .background(fill, in: RoundedRectangle(cornerRadius: 34))
    }
}
struct Heading: View {
    let t: String
    var body: some View { Text(t).font(Theme.font(64)).foregroundColor(Theme.ink).padding(.top, 40) }
}
struct LabeledField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        VStack(spacing: 6) {
            Pill(text: label, size: 20)
            TextField("", text: $text).font(Theme.font(22)).foregroundColor(Theme.ink)
                .multilineTextAlignment(.center).autocorrectionDisabled()
                .padding(.vertical, 14).background(Theme.field, in: RoundedRectangle(cornerRadius: 30))
        }
    }
}

// MARK: - Events (edit this list to add or rename events)
enum Events {
    static let all = [
        "animatronics",
        "architectural design",
        "artificial intelligence",
        "audio podcasting",
        "automated manufacturing systems",
        "biotechnology design",
        "board game design",
        "cad architecture",
        "cad engineering",
        "cad foundations",
        "career prep",
        "challenging technology issues",
        "chapter team",
        "childrens stories",
        "coding",
        "community service video",
        "construction challenge",
        "cybersecurity",
        "data science",
        "debating tech issues",
        "digital photography",
        "digital video production",
        "dragster design",
        "drone challenge",
        "electrical applications",
        "engineering design",
        "extemporaneous speech",
        "fashion design",
        "flight",
        "flight endurance",
        "forensic science technology",
        "future technology teacher",
        "hybrid racer xl",
        "interior design",
        "inventions and innovations",
        "manufacturing prototype",
        "mass production",
        "mechanical engineering",
        "medical technology",
        "microcontroller design",
        "music production",
        "off the grid",
        "on demand video",
        "photographic technology",
        "prepared presentation",
        "prepared speech",
        "problem solving",
        "promotional design",
        "robotics",
        "software development",
        "solar racer",
        "stem animation",
        "stem mass media",
        "structural design",
        "system control technology",
        "tech bowl",
        "technical design",
        "transportation modeling",
        "video game design",
        "virtual reality",
        "vlogging",
        "webmaster",
        "website design"
    ]
}

/// Type to narrow the list, then tap an event to select it.
struct EventPicker: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var matches: [String] {
        let t = text.lowercased().trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return Events.all }
        let tokens = t.split(separator: " ").map(String.init)
        return Events.all.filter { e in tokens.allSatisfy { e.contains($0) } }
            .sorted { ($0.hasPrefix(t) ? 0 : 1) < ($1.hasPrefix(t) ? 0 : 1) }
    }

    var body: some View {
        VStack(spacing: 6) {
            Pill(text: "enter event name:", size: 20)
            TextField("", text: $text, prompt: Text("start typing…").foregroundColor(Theme.ink.opacity(0.5)))
                .font(Theme.font(22)).foregroundColor(Theme.ink).multilineTextAlignment(.center)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .focused($focused)
                .padding(.vertical, 14).background(Theme.field, in: RoundedRectangle(cornerRadius: 30))
            if focused {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(matches, id: \.self) { e in
                            Button { text = e; focused = false } label: {
                                Text(e).font(Theme.font(20)).foregroundColor(Theme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            }
                            Divider()
                        }
                        if matches.isEmpty { Text("No matching event").font(Theme.font(18)).foregroundColor(Theme.ink).padding(14) }
                    }
                }
                .frame(maxHeight: 220)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 24))
            }
        }
    }
}

// MARK: - Navigation
enum Screen { case landing, role, judge, login, home }

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var screen = Screen.landing
    @AppStorage("role") private var role = ""   // "judge" or "student", locked once chosen

    func destination(_ r: String) -> Screen { r == "judge" ? .judge : (store.ids.isEmpty ? .login : .home) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GridBackground()
            Group {
                switch screen {
                case .landing: Landing { screen = role.isEmpty ? .role : destination(role) }
                case .role: RoleView { role = $0; screen = destination($0) }
                case .judge: JudgeView()
                case .login: LoginView { screen = .home }
                case .home: HomeView { screen = .login }
                }
            }
            if screen == .role || (screen == .login && !store.ids.isEmpty) {   // no way back across roles
                Button {
                    screen = screen == .role ? .landing : .home
                } label: {
                    Image(systemName: "chevron.left").font(.title2.bold()).foregroundColor(Theme.ink).padding(18)
                }
            }
        }
    }
}

// MARK: - Screens
struct Landing: View {
    let go: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("TSA").font(Theme.font(120)).foregroundColor(Theme.ink)
            Text("feedback portal").font(Theme.font(36)).foregroundColor(Theme.ink)
            Button(action: go) {
                HStack {
                    Text("it's feedback time!").font(Theme.font(32)).multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 40, weight: .heavy))
                }
                .foregroundColor(Theme.ink).padding(28)
                .background(Theme.pill, in: RoundedRectangle(cornerRadius: 44))
            }.padding(.top, 60)
            Spacer(); Spacer()
        }.padding(.horizontal, 28)
    }
}

struct RoleView: View {
    let choose: (String) -> Void
    @State private var pending = ""
    var body: some View {
        VStack(spacing: 28) {
            Text("I'm a:").font(Theme.font(48, bold: true)).foregroundColor(Theme.ink).padding(.top, 50)
            Button { pending = "judge" } label: { Pill(text: "Judge", size: 52) }
            Button { pending = "student" } label: { Pill(text: "Student", size: 52) }
            Spacer()
        }
        .padding(.horizontal, 28)
        .alert("Continue as a \(pending)?", isPresented: Binding(get: { !pending.isEmpty }, set: { if !$0 { pending = "" } })) {
            Button("Continue") { let r = pending; choose(r) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You can't switch roles on this device afterwards.") }
    }
}

struct JudgeView: View {
    @EnvironmentObject var store: Store
    @State private var sid = ""
    @State private var event = ""
    @State private var kind = "comment card"
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var busy = false
    @State private var status = ""

    func check(_ t: String) -> some View {
        Button { kind = t } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.pill).frame(width: 34, height: 34)
                    if kind == t { Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundColor(.black) }
                }
                Text(t).font(Theme.font(30)).foregroundColor(Theme.ink)
                Spacer()
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Heading(t: "Judge")
                LabeledField(label: "enter student ID:", text: $sid)
                EventPicker(text: $event)
                Text("this is a:").font(Theme.font(34)).foregroundColor(Theme.ink)
                VStack(alignment: .leading, spacing: 10) { check("rubric"); check("comment card") }.padding(.horizontal, 60)
                PhotosPicker(selection: $item, matching: .images) { Pill(text: "upload a photo", size: 30) }
                Button { showCamera = true } label: { Pill(text: "take a photo", size: 30) }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Button { Task { await send() } } label: { Pill(text: busy ? "Sending…" : "Send!", fill: Theme.ink, fg: .white, size: 44) }
                    .disabled(busy)
                if !status.isEmpty { Text(status).font(Theme.font(18)).foregroundColor(Theme.ink) }
            }.padding(.horizontal, 28).padding(.bottom, 30)
        }
        .fullScreenCover(isPresented: $showCamera) { CameraPicker(image: $image).ignoresSafeArea() }
        .onChange(of: item) { new in
            Task { if let d = try? await new?.loadTransferable(type: Data.self) { image = UIImage(data: d) } }
        }
    }

    func send() async {
        let ev = event.trimmingCharacters(in: .whitespaces).lowercased()
        guard let image, !sid.isEmpty else { status = "Add a photo and a student ID."; return }
        guard Events.all.contains(ev) else { status = "Pick an event from the list."; return }
        busy = true; defer { busy = false }
        do {
            try await store.send(image, to: sid, event: ev, kind: kind)
            self.image = nil; item = nil; sid = ""; event = ""; status = "Sent ✓"
        } catch { status = error.localizedDescription }
    }
}

struct LoginView: View {
    @EnvironmentObject var store: Store
    let done: () -> Void
    @State private var f = Array(repeating: "", count: 6)
    @State private var err = ""
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Heading(t: "Student")
                Pill(text: store.ids.isEmpty ? "Login: Enter up to 6 IDs!" : "Add more IDs (\(6 - store.ids.count) left)", size: 30)
                ForEach(0..<6, id: \.self) { i in
                    TextField("", text: $f[i], prompt: Text("student ID \(i + 1):").foregroundColor(Theme.ink))
                        .font(Theme.font(26)).foregroundColor(Theme.ink).multilineTextAlignment(.center)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(.vertical, 16).background(Theme.field, in: RoundedRectangle(cornerRadius: 34))
                        .disabled(i >= 6 - store.ids.count).opacity(i >= 6 - store.ids.count ? 0.4 : 1)
                }
                Button { Task {
                    busy = true; defer { busy = false }
                    do { try await store.register(f); done() } catch { err = error.localizedDescription }
                } } label: { Pill(text: busy ? "Working…" : "Go!  ➜", size: 32) }.disabled(busy)
                if !err.isEmpty { Text(err).font(Theme.font(18)).foregroundColor(.red) }
            }.padding(.horizontal, 28).padding(.bottom, 30)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var store: Store
    let add: () -> Void
    @State private var sel: InboxMessage?
    @State private var editing: IDItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Heading(t: "Student")
                Pill(text: "Inbox", size: 36)
                if store.messages.isEmpty { Text("Nothing here yet").font(Theme.font(20)).foregroundColor(Theme.ink) }
                ForEach(store.messages) { m in
                    Button { sel = m } label: { Pill(text: "\(m.to) - \(m.event)\n\(m.kind)", fill: Theme.field, size: 22) }
                }
                Pill(text: "All event IDs", size: 32).padding(.top, 10)
                ForEach(store.ids, id: \.self) { id in
                    Button { editing = IDItem(id: id) } label: { Pill(text: "\(id)  ✎", fill: Theme.field, size: 30) }
                }
                if store.ids.count < 6 { Button(action: add) { Pill(text: "Add more!", fill: Theme.ink, fg: .white, size: 32) } }
            }.padding(.horizontal, 28).padding(.bottom, 30)
        }
        .sheet(item: $sel) { MessageSheet(message: $0) }
        .sheet(item: $editing) { EditIDSheet(sid: $0.id) }
    }
}

struct IDItem: Identifiable { let id: String }

struct EditIDSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let sid: String
    @State private var text = ""
    @State private var err = ""
    @State private var busy = false
    @State private var confirmRemove = false

    var body: some View {
        ZStack {
            GridBackground()
            VStack(spacing: 14) {
                Text("Edit ID").font(Theme.font(40)).foregroundColor(Theme.ink).padding(.top, 30)
                TextField("", text: $text).font(Theme.font(26)).foregroundColor(Theme.ink).multilineTextAlignment(.center)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.vertical, 16).background(Theme.field, in: RoundedRectangle(cornerRadius: 34))
                Button { Task { await save() } } label: {
                    Pill(text: busy ? "Working…" : "Save", fill: Theme.ink, fg: .white, size: 30)
                }.disabled(busy)
                Button { confirmRemove = true } label: { Text("Remove this ID").font(Theme.font(22)).foregroundColor(.red) }
                Text("Changing or removing an ID deletes any messages sent to the old one.")
                    .font(Theme.font(16)).foregroundColor(Theme.ink).multilineTextAlignment(.center)
                if !err.isEmpty { Text(err).font(Theme.font(18)).foregroundColor(.red) }
                Spacer()
            }.padding(.horizontal, 28)
        }
        .onAppear { text = sid }
        .alert("Remove \(sid)?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { Task { await run { try await store.remove(sid) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Messages sent to this ID will be deleted.") }
    }

    func save() async {
        if text.trimmingCharacters(in: .whitespaces).lowercased() == sid { dismiss(); return }
        await run { try await store.rename(sid, to: text) }
    }
    func run(_ work: () async throws -> Void) async {
        busy = true; defer { busy = false }
        do { try await work(); dismiss() } catch { err = error.localizedDescription }
    }
}

struct MessageSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let message: InboxMessage
    @State private var image: UIImage?
    @State private var status = ""

    var body: some View {
        ZStack {
            GridBackground()
            ScrollView {
                VStack(spacing: 14) {
                    Text("\(message.to) - \(message.event)").font(Theme.font(28, bold: true)).foregroundColor(Theme.ink).multilineTextAlignment(.center)
                    Text("\(message.kind) · \(message.ts.formatted(date: .abbreviated, time: .shortened))")
                        .font(Theme.font(18)).foregroundColor(Theme.ink)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16))
                        Button { Task { await save(image) } } label: {
                            Pill(text: "Save to Photos & delete", fill: Theme.ink, fg: .white, size: 24)
                        }
                    } else { Text(status.isEmpty ? "Decrypting…" : status).font(Theme.font(20)).foregroundColor(Theme.ink) }
                    Button { Task { await store.delete(message); dismiss() } } label: {
                        Text("Delete").font(Theme.font(22)).foregroundColor(.red)
                    }
                    if !status.isEmpty && image != nil { Text(status).font(Theme.font(16)).foregroundColor(Theme.ink) }
                }.padding(28)
            }
        }
        .onAppear { do { image = try store.decrypt(message) } catch { status = error.localizedDescription } }
    }

    func save(_ img: UIImage) async {
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: img) }
            await store.delete(message); dismiss()   // deleted only after the save succeeds
        } catch { status = "Save failed, so nothing was deleted." }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController(); p.sourceType = .camera; p.delegate = context.coordinator; return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }
    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let p: CameraPicker
        init(_ p: CameraPicker) { self.p = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            p.image = info[.originalImage] as? UIImage; p.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { p.dismiss() }
    }
}

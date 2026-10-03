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

// MARK: - Navigation
enum Screen { case landing, role, judge, login, home }

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var screen = Screen.landing

    var body: some View {
        ZStack(alignment: .topLeading) {
            GridBackground()
            Group {
                switch screen {
                case .landing: Landing { screen = .role }
                case .role: RoleView(judge: { screen = .judge }, student: { screen = store.ids.isEmpty ? .login : .home })
                case .judge: JudgeView()
                case .login: LoginView { screen = .home }
                case .home: HomeView { screen = .login }
                }
            }
            if screen != .landing {
                Button {
                    let back: [Screen: Screen] = [.role: .landing, .judge: .role, .home: .role]
                    screen = back[screen] ?? (store.ids.isEmpty ? .role : .home)
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
    let judge: () -> Void, student: () -> Void
    var body: some View {
        VStack(spacing: 28) {
            Text("I'm a:").font(Theme.font(48, bold: true)).foregroundColor(Theme.ink).padding(.top, 50)
            Button(action: judge) { Pill(text: "Judge", size: 52) }
            Button(action: student) { Pill(text: "Student", size: 52) }
            Spacer()
        }.padding(.horizontal, 28)
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
                LabeledField(label: "enter event name:", text: $event)
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
        guard let image, !sid.isEmpty, !event.isEmpty else { status = "Add a photo, student ID and event name."; return }
        busy = true; defer { busy = false }
        do {
            try await store.send(image, to: sid, event: event, kind: kind)
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
                ForEach(store.ids, id: \.self) { Pill(text: $0, fill: Theme.field, size: 30) }
                if store.ids.count < 6 { Button(action: add) { Pill(text: "Add more!", fill: Theme.ink, fg: .white, size: 32) } }
            }.padding(.horizontal, 28).padding(.bottom, 30)
        }
        .sheet(item: $sel) { MessageSheet(message: $0) }
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

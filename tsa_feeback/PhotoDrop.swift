// PhotoDrop.swift — iOS 16+, SwiftUI, CryptoKit, Firebase (Auth + Firestore)
import SwiftUI
import PhotosUI
import Photos
import CryptoKit
import Security
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import FirebaseCore

// MARK: - App entry
@main
struct PhotoDropApp: App {
    @StateObject private var store = Store()
    init() { FirebaseApp.configure() }
    var body: some Scene {
        WindowGroup {
            TabView {
                SendView().tabItem { Label("Send", systemImage: "paperplane") }
                InboxView().tabItem { Label("Inbox", systemImage: "tray") }
            }
            .environmentObject(store)
        }
    }
}

// MARK: - Encryption (end to end: only the student's private key can open a photo)
enum Vault {
    private static func derive(_ s: SharedSecret, _ a: Data, _ b: Data) -> SymmetricKey {
        s.hkdfDerivedSymmetricKey(using: SHA256.self, salt: a + b,
                                  sharedInfo: Data("photodrop".utf8), outputByteCount: 32)
    }
    /// Sender side: fresh ephemeral key per photo + student's public key -> AES-GCM.
    static func seal(_ data: Data, to pub: Data) throws -> (ephemeral: Data, box: Data) {
        let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pub)
        let eph = Curve25519.KeyAgreement.PrivateKey()
        let key = derive(try eph.sharedSecretFromKeyAgreement(with: recipient),
                         eph.publicKey.rawRepresentation, pub)
        return (eph.publicKey.rawRepresentation, try AES.GCM.seal(data, using: key).combined!)
    }
    /// Student side.
    static func open(box: Data, ephemeral: Data, with priv: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        let sender = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeral)
        let key = derive(try priv.sharedSecretFromKeyAgreement(with: sender),
                         ephemeral, priv.publicKey.rawRepresentation)
        return try AES.GCM.open(try AES.GCM.SealedBox(combined: box), using: key)
    }
}

// MARK: - Private key storage (Keychain, syncs via iCloud Keychain)
enum KeyStore {
    private static func query(_ sid: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrAccount as String: "photodrop.\(sid)",
         kSecAttrSynchronizable as String: true]
    }
    static func save(_ key: Curve25519.KeyAgreement.PrivateKey, sid: String) {
        SecItemDelete(query(sid) as CFDictionary)
        var q = query(sid); q[kSecValueData as String] = key.rawRepresentation
        SecItemAdd(q as CFDictionary, nil)
    }
    static func load(_ sid: String) -> Curve25519.KeyAgreement.PrivateKey? {
        var q = query(sid)
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: d)
    }
}

// MARK: - Backend (Firestore holds ciphertext only; see firestore.rules)
struct InboxMessage: Identifiable {
    let id: String, from: String, ts: Date, ephemeral: Data, box: Data
}
struct AppError: LocalizedError { let errorDescription: String? ; init(_ m: String) { errorDescription = m } }

@MainActor
final class Store: ObservableObject {
    @Published var messages: [InboxMessage] = []
    @Published var mySID: String? = UserDefaults.standard.string(forKey: "sid")
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    init() { listen() }

    private func signIn() async throws -> String {
        // Anonymous auth keeps this short. Swap in Sign in with Apple for accounts that survive reinstalls.
        if Auth.auth().currentUser == nil { try await Auth.authS().signInAnonymously() }
        return Auth.auth().currentUser!.uid
    }

    func register(_ rawID: String) async throws {
        let sid = rawID.trimmingCharacters(in: .whitespaces).lowercased()
        guard !sid.isEmpty, !sid.contains("/") else { throw AppError("Enter a valid student ID.") }
        let uid = try await signIn()
        let ref = db.document("students/\(sid)")
        let snap = try await ref.getDocument()
        if snap.exists, snap.get("uid") as? String != uid { throw AppError("That ID is already claimed.") }
        let key = KeyStore.load(sid) ?? Curve25519.KeyAgreement.PrivateKey()
        KeyStore.save(key, sid: sid)
        try await ref.setData(["uid": uid, "pub": key.publicKey.rawRepresentation])
        UserDefaults.standard.set(sid, forKey: "sid")
        mySID = sid
        listen()
    }

    func send(_ image: UIImage, to rawID: String, fromName: String) async throws {
        let sid = rawID.trimmingCharacters(in: .whitespaces).lowercased()
        let uid = try await signIn()
        let s = try await db.document("students/\(sid)").getDocument()
        guard let pub = s.get("pub") as? Data else { throw AppError("No student is registered with that ID.") }
        guard let jpeg = image.jpegUnder(650_000) else { throw AppError("Couldn't process that photo.") }
        let sealed = try Vault.seal(jpeg, to: pub)
        try await db.collection("students/\(sid)/inbox").addDocument(data: [
            "from": uid, "fromName": fromName, "eph": sealed.ephemeral,
            "box": sealed.box, "ts": FieldValue.serverTimestamp()])
    }

    func delete(_ m: InboxMessage) async {
        guard let sid = mySID else { return }
        try? await db.document("students/\(sid)/inbox/\(m.id)").delete()
    }

    func decrypt(_ m: InboxMessage) throws -> UIImage {
        guard let sid = mySID, let key = KeyStore.load(sid) else { throw AppError("Private key not found on this device.") }
        guard let img = UIImage(data: try Vault.open(box: m.box, ephemeral: m.ephemeral, with: key))
        else { throw AppError("Corrupt photo.") }
        return img
    }

    private func listen() {
        listener?.remove()
        guard let sid = mySID else { return }
        listener = db.collection("students/\(sid)/inbox").order(by: "ts", descending: true)
            .addSnapshotListener { [weak self] snap, _ in
                let list: [InboxMessage] = snap?.documents.compactMap { d in
                    guard let e = d["eph"] as? Data, let b = d["box"] as? Data else { return nil }
                    return InboxMessage(id: d.documentID, from: d["fromName"] as? String ?? "",
                                        ts: (d["ts"] as? Timestamp)?.dateValue() ?? Date(), ephemeral: e, box: b)
                } ?? []
                Task { @MainActor in self?.messages = list }
            }
    }
}

extension UIImage {
    /// Downscale to 1400px and compress until under `limit` bytes (Firestore docs max out at 1 MB).
    func jpegUnder(_ limit: Int) -> Data? {
        let k = min(1, 1400 / max(size.width, size.height))
        let target = CGSize(width: size.width * k, height: size.height * k)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let small = UIGraphicsImageRenderer(size: target, format: f).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        var q: CGFloat = 0.85
        while q > 0.2 {
            if let d = small.jpegData(compressionQuality: q), d.count <= limit { return d }
            q -= 0.15
        }
        return small.jpegData(compressionQuality: 0.2)
    }
}

// MARK: - Send tab
struct SendView: View {
    @EnvironmentObject var store: Store
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var sid = ""
    @State private var name = ""
    @State private var status = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $item, matching: .images) {
                        if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240) }
                        else { Label("Choose a photo", systemImage: "photo") }
                    }
                }
                Section {
                    TextField("Student ID", text: $sid).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Your name (shown to student, optional)", text: $name)
                }
                Section {
                    Button(busy ? "Sending…" : "Encrypt & send") { Task { await send() } }
                        .disabled(image == nil || sid.isEmpty || busy)
                    if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Send photo")
            .onChange(of: item) { new in
                Task {
                    if let d = try? await new?.loadTransferable(type: Data.self) { image = UIImage(data: d) }
                }
            }
        }
    }

    func send() async {
        guard let image else { return }
        busy = true; defer { busy = false }
        do {
            try await store.send(image, to: sid, fromName: name)
            self.image = nil; item = nil; sid = ""; status = "Sent ✓ (encrypted end to end)"
        } catch { status = error.localizedDescription }
    }
}

// MARK: - Inbox tab (email style: list + reading pane)
struct InboxView: View {
    @EnvironmentObject var store: Store
    @State private var selected: String?

    var body: some View {
        if store.mySID == nil { RegisterView() }
        else {
            NavigationSplitView {
                List(store.messages, selection: $selected) { m in
                    VStack(alignment: .leading) {
                        Text(m.from.isEmpty ? "Photo from someone" : "Photo from \(m.from)").bold()
                        Text(m.ts.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .overlay { if store.messages.isEmpty { Text("Inbox is empty").foregroundStyle(.secondary) } }
                .navigationTitle("Inbox")
            } detail: {
                if let m = store.messages.first(where: { $0.id == selected }) {
                    MessageDetail(message: m).id(m.id)
                } else { Text("Select a message").foregroundStyle(.secondary) }
            }
        }
    }
}

struct MessageDetail: View {
    @EnvironmentObject var store: Store
    let message: InboxMessage
    @State private var image: UIImage?
    @State private var status = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(message.from.isEmpty ? "Photo from someone" : "Photo from \(message.from)").font(.title3.bold())
                Text(message.ts.formatted()).font(.caption).foregroundStyle(.secondary)
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 10))
                    Button("Save to Photos & delete from server") { Task { await save(image) } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Decrypt & open") {
                        do { image = try store.decrypt(message) } catch { status = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                }
                Button("Delete", role: .destructive) { Task { await store.delete(message) } }
                if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary) }
            }.padding()
        }
    }

    func save(_ img: UIImage) async {
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: img) }
            await store.delete(message)   // only deleted once the save succeeded
        } catch { status = "Save failed, so nothing was deleted." }
    }
}

struct RegisterView: View {
    @EnvironmentObject var store: Store
    @State private var sid = ""
    @State private var err = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("This creates a private key stored in your Keychain. Only you can open photos sent to you.")) {
                    TextField("Your student ID", text: $sid).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Register") { Task {
                        do { try await store.register(sid) } catch { err = error.localizedDescription }
                    } }
                }
                if !err.isEmpty { Text(err).foregroundStyle(.red) }
            }.navigationTitle("Claim your ID")
        }
    }
}

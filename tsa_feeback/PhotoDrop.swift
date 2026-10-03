import SwiftUI
import Combine
import CryptoKit
import Security
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

@main
struct PhotoDropApp: App {
    @StateObject private var store = Store()
    init() { FirebaseApp.configure() }
    var body: some Scene { WindowGroup { RootView().environmentObject(store) } }
}

// MARK: - End-to-end encryption (only the student's private key can open a message)
enum Vault {
    private static func derive(_ s: SharedSecret, _ a: Data, _ b: Data) -> SymmetricKey {
        s.hkdfDerivedSymmetricKey(using: SHA256.self, salt: a + b,
                                  sharedInfo: Data("photodrop".utf8), outputByteCount: 32)
    }
    /// Seals several payloads (metadata + photo) under one fresh ephemeral key.
    static func seal(_ parts: [Data], to pub: Data) throws -> (ephemeral: Data, boxes: [Data]) {
        let r = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pub)
        let eph = Curve25519.KeyAgreement.PrivateKey()
        let key = derive(try eph.sharedSecretFromKeyAgreement(with: r), eph.publicKey.rawRepresentation, pub)
        return (eph.publicKey.rawRepresentation, try parts.map { try AES.GCM.seal($0, using: key).combined! })
    }
    static func open(box: Data, ephemeral: Data, with priv: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        let s = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeral)
        let key = derive(try priv.sharedSecretFromKeyAgreement(with: s), ephemeral, priv.publicKey.rawRepresentation)
        return try AES.GCM.open(try AES.GCM.SealedBox(combined: box), using: key)
    }
}

// One private key per student account, kept in the Keychain (syncs via iCloud Keychain).
// The same public key is published under each of the student's IDs.
enum KeyStore {
    private static var q: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrAccount as String: "photodrop.identity",
         kSecAttrSynchronizable as String: true]
    }
    static func load() -> Curve25519.KeyAgreement.PrivateKey? {
        var a = q; a[kSecReturnData as String] = true; a[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(a as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: d)
    }
    static func loadOrCreate() -> Curve25519.KeyAgreement.PrivateKey {
        if let k = load() { return k }
        let k = Curve25519.KeyAgreement.PrivateKey()
        var a = q; a[kSecValueData as String] = k.rawRepresentation
        SecItemAdd(a as CFDictionary, nil)
        return k
    }
}

// MARK: - Models
struct InboxMessage: Identifiable {
    let id: String, to: String
    let ts: Date
    let ephemeral: Data, box: Data
    let event: String, kind: String      // decrypted metadata
}
struct Meta: Codable { let event: String, kind: String }
struct AppError: LocalizedError { let errorDescription: String?; init(_ m: String) { errorDescription = m } }

// MARK: - Backend (Firestore only ever holds ciphertext; same firestore.rules as before)
@MainActor
final class Store: ObservableObject {
    @Published var messages: [InboxMessage] = []
    @Published var ids: [String] = UserDefaults.standard.stringArray(forKey: "sids") ?? []
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var buckets: [String: [InboxMessage]] = [:]

    init() { listen() }

    private func signIn() async throws -> String {
        if Auth.auth().currentUser == nil { try await Auth.auth().signInAnonymously() }
        return Auth.auth().currentUser!.uid
    }

    /// Student: claim up to 6 IDs in total.
    func register(_ raw: [String]) async throws {
        var seen = Set(ids)
        let new = raw.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && !$0.contains("/") && seen.insert($0).inserted }
        guard !new.isEmpty else { throw AppError("Enter at least one new ID.") }
        guard ids.count + new.count <= 6 else { throw AppError("You can have up to 6 IDs.") }
        let uid = try await signIn()
        for sid in new {
            let s = try await db.document("students/\(sid)").getDocument()
            if s.exists, s.get("uid") as? String != uid { throw AppError("ID \(sid) is already claimed.") }
        }
        let pub = KeyStore.loadOrCreate().publicKey.rawRepresentation
        for sid in new { try await db.document("students/\(sid)").setData(["uid": uid, "pub": pub]) }
        ids += new
        UserDefaults.standard.set(ids, forKey: "sids")
        listen()
    }

    private func purge(_ sid: String) async throws {
        let snap = try await db.collection("students/\(sid)/inbox").getDocuments()
        for d in snap.documents { try await d.reference.delete() }   // messages first, while we still own the ID
        try await db.document("students/\(sid)").delete()
    }

    /// Student: give up an ID (messages sent to it are deleted).
    func remove(_ sid: String) async throws {
        try await purge(sid)
        ids.removeAll { $0 == sid }
        UserDefaults.standard.set(ids, forKey: "sids")
        listen()
    }

    /// Student: change an ID (messages sent to the old one are deleted).
    func rename(_ old: String, to raw: String) async throws {
        let new = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !new.isEmpty, !new.contains("/") else { throw AppError("Enter a valid ID.") }
        guard !ids.contains(new) else { throw AppError("You already have that ID.") }
        let uid = try await signIn()
        let s = try await db.document("students/\(new)").getDocument()
        if s.exists, s.get("uid") as? String != uid { throw AppError("ID \(new) is already claimed.") }
        let pub = KeyStore.loadOrCreate().publicKey.rawRepresentation
        try await db.document("students/\(new)").setData(["uid": uid, "pub": pub])
        try await purge(old)
        if let i = ids.firstIndex(of: old) { ids[i] = new }
        UserDefaults.standard.set(ids, forKey: "sids")
        listen()
    }

    /// Judge: send a photo plus event name and type (rubric / comment card), all encrypted.
    func send(_ image: UIImage, to raw: String, event: String, kind: String) async throws {
        let sid = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let uid = try await signIn()
        let s = try await db.document("students/\(sid)").getDocument()
        guard let pub = s.get("pub") as? Data else { throw AppError("No student has registered that ID yet.") }
        guard let jpeg = image.jpegUnder(650_000) else { throw AppError("Couldn't process that photo.") }
        let meta = try JSONEncoder().encode(Meta(event: event, kind: kind))
        let sealed = try Vault.seal([meta, jpeg], to: pub)
        try await db.collection("students/\(sid)/inbox").addDocument(data: [
            "from": uid, "eph": sealed.ephemeral, "meta": sealed.boxes[0],
            "box": sealed.boxes[1], "ts": FieldValue.serverTimestamp()])
    }

    func delete(_ m: InboxMessage) async {
        try? await db.document("students/\(m.to)/inbox/\(m.id)").delete()
    }

    func decrypt(_ m: InboxMessage) throws -> UIImage {
        guard let key = KeyStore.load() else { throw AppError("Private key not found on this device.") }
        guard let img = UIImage(data: try Vault.open(box: m.box, ephemeral: m.ephemeral, with: key))
        else { throw AppError("Corrupt photo.") }
        return img
    }

    private func listen() {
        listeners.forEach { $0.remove() }
        listeners = []; buckets = [:]; messages = []
        guard let key = KeyStore.load() else { return }
        for sid in ids {
            listeners.append(db.collection("students/\(sid)/inbox").addSnapshotListener { [weak self] snap, _ in
                let list: [InboxMessage] = snap?.documents.compactMap { d in
                    guard let e = d["eph"] as? Data, let m = d["meta"] as? Data, let b = d["box"] as? Data,
                          let mj = try? Vault.open(box: m, ephemeral: e, with: key),
                          let meta = try? JSONDecoder().decode(Meta.self, from: mj) else { return nil }
                    return InboxMessage(id: d.documentID, to: sid,
                                        ts: (d["ts"] as? Timestamp)?.dateValue() ?? Date(),
                                        ephemeral: e, box: b, event: meta.event, kind: meta.kind)
                } ?? []
                Task { @MainActor in
                    self?.buckets[sid] = list
                    self?.messages = (self?.buckets.values.flatMap { $0 } ?? []).sorted { $0.ts > $1.ts }
                }
            })
        }
    }
}

extension UIImage {
    /// Downscale to 1400px and compress under `limit` bytes (Firestore docs max out at 1 MB).
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

import Foundation
import Security

enum ServiceError: LocalizedError {
    case message(String)
    case authenticationRequired
    var errorDescription: String? { switch self { case .message(let text): text; case .authenticationRequired: "Sign in to access your AsunaTracks account." } }
}

/// Uses the same HTTPS session API as the existing AsunaTracks website.
actor APIClient {
    static let shared = APIClient()
    static let origin = URL(string: "https://asunatracks.space")!
    private let session: URLSession
    init(configuration: URLSessionConfiguration = .default, restoreSession: Bool = true) {
        let config = configuration
        config.timeoutIntervalForRequest = 30
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        session = URLSession(configuration: config)
        if restoreSession { SessionVault.restore() }
    }
    func request<T: Decodable>(_ path: String, query: [String: String] = [:], method: String = "GET", body: Data? = nil) async throws -> T {
        var components = URLComponents(url: Self.origin.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ServiceError.message("The server did not respond. Please try again.") }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 && path != "api/auth/login" { throw ServiceError.authenticationRequired }
            let message = try? Coding.decoder.decode(APIMessage.self, from: data)
            throw ServiceError.message(message?.error ?? (response.statusCode == 401 ? "The username or password was not accepted. Check them and try again." : "AsunaTracks returned an error (\(response.statusCode)). Please try again."))
        }
        if path == "api/me" { SessionVault.save() }
        do { return try Coding.decoder.decode(T.self, from: data) }
        catch { throw ServiceError.message("AsunaTracks returned an unexpected response. Please try again later.") }
    }
    func login(username: String, password: String) async throws -> UserResponse {
        let body = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let result: UserResponse = try await request("api/auth/login", method: "POST", body: body)
        SessionVault.save()
        return result
    }
    func logout() async throws {
        let _: UserResponse = try await request("api/auth/logout", method: "POST", body: Data("{}".utf8))
        SessionVault.clear()
    }
    func save(_ media: Media, fields: TrackingFields) async throws {
        var object = try JSONSerialization.jsonObject(with: Coding.encoder.encode(fields)) as! [String: Any]
        object["media_id"] = media.id
        object["media_type"] = media.mediaType
        let _: DetailResponse = try await request("api/list", method: "POST", body: JSONSerialization.data(withJSONObject: object))
    }
    func advance(_ entry: ListEntry) async throws {
        guard entry.canAdvance else { return }
        if entry.media.mediaType == "anime" {
            let _: DetailResponse = try await request("api/media/anime/\(entry.media.id)/episodes/\((entry.progress ?? 0) + 1)/watched", method: "POST", body: Data("{}".utf8))
        } else {
            let next = (entry.progress ?? 0) + 1
            let status = entry.media.total > 0 && next >= entry.media.total ? "completed" : entry.status
            try await save(entry.media, fields: TrackingFields(status: status, progress: next,
                progressVolumes: entry.progressVolumes, rating: entry.rating, favorite: entry.favorite, notes: entry.notes,
                repeatCount: entry.repeatCount, startDate: entry.startDate, finishDate: entry.finishDate))
        }
    }
}

/// Sessions stay in the device-local Keychain, shared only with this app's widgets.
enum SessionVault {
    private struct SavedCookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let secure: Bool
        let expires: Date?
    }
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "space.asunatracks.session", kSecAttrAccount as String: "cookies"]
    private static var widgetQuery: [String: Any] {
        var result = query
        result[kSecAttrService as String] = "space.asunatracks.widget-session"
        #if os(macOS)
        result[kSecAttrAccessGroup as String] = "B6NP2879G2.space.asunatracks.widget-session"
        result[kSecUseDataProtectionKeychain as String] = true
        #else
        result[kSecAttrAccessGroup as String] = "group.space.asunatracks.apple"
        #endif
        return result
    }
    static func save() {
        let cookies = HTTPCookieStorage.shared.cookies(for: APIClient.origin) ?? []
        let rows = cookies.map { cookie in
            SavedCookie(name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path,
                secure: cookie.isSecure, expires: cookie.expiresDate)
        }
        guard let data = try? JSONEncoder().encode(rows) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let privateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if privateStatus == errSecItemNotFound { SecItemAdd(item as CFDictionary, nil) }
        #if !os(macOS)
        var sharedItem = widgetQuery
        sharedItem[kSecValueData as String] = data
        sharedItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemUpdate(widgetQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound { SecItemAdd(sharedItem as CFDictionary, nil) }
        #endif
    }
    static func restore() {
        #if os(macOS)
        var request = query
        #else
        var request = widgetQuery
        #endif
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        if SecItemCopyMatching(request as CFDictionary, &result) != errSecSuccess {
            request = query
            request[kSecReturnData as String] = true
            guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else { return }
        }
        guard let data = result as? Data, let rows = try? JSONDecoder().decode([SavedCookie].self, from: data) else { return }
        for row in rows {
            if let expires = row.expires, expires < Date() { continue }
            var properties: [HTTPCookiePropertyKey: Any] = [.name: row.name, .value: row.value, .domain: row.domain, .path: row.path]
            if row.secure { properties[.secure] = "TRUE" }
            if let expires = row.expires { properties[.expires] = expires }
            if let cookie = HTTPCookie(properties: properties) { HTTPCookieStorage.shared.setCookie(cookie) }
        }
        save() // Migrate existing sign-ins without asking for the password again.
    }
    static func clear() {
        SecItemDelete(query as CFDictionary)
        #if !os(macOS)
        SecItemDelete(widgetQuery as CFDictionary)
        #endif
        for cookie in HTTPCookieStorage.shared.cookies(for: APIClient.origin) ?? [] { HTTPCookieStorage.shared.deleteCookie(cookie) }
    }
}

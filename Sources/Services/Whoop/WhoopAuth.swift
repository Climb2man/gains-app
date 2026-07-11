import Foundation

/// The MFA challenge names Cognito may return that we know how to answer.
enum WhoopMfaChallenge: String, Sendable, Equatable {
    case smsMfa = "SMS_MFA"
    case softwareTokenMfa = "SOFTWARE_TOKEN_MFA"
    case emailOtp = "EMAIL_OTP"

    /// The ChallengeResponses key that carries the code for this challenge type.
    var codeField: String {
        switch self {
        case .smsMfa: return "SMS_MFA_CODE"
        case .softwareTokenMfa: return "SOFTWARE_TOKEN_MFA_CODE"
        case .emailOtp: return "EMAIL_OTP_CODE"
        }
    }
}

/// Tokens minted by Cognito. `expiresAt` is epoch ms (decoded from the JWT).
struct WhoopCognitoTokens: Sendable, Equatable {
    let accessToken: String
    /// nil on the refresh flow: the caller keeps the existing one in that case.
    let refreshToken: String?
    let expiresAt: Double
}

/// Result of initiateAuth: either tokens, an MFA challenge to answer, or failure.
enum WhoopCognitoLoginResult: Sendable, Equatable {
    case ok(WhoopCognitoTokens)
    case mfa(challenge: WhoopMfaChallenge, session: String, username: String)
    case failed
}

/// The Cognito auth transport. Behind a protocol so the network layer is swappable in tests.
protocol WhoopAuthing: Sendable {
    func initiateAuth(email: String, password: String) async -> WhoopCognitoLoginResult
    func respondToMfa(
        challenge: WhoopMfaChallenge, session: String, username: String, code: String
    ) async -> WhoopCognitoTokens?
    func refreshTokens(refreshToken: String) async -> WhoopCognitoTokens?
}

/// Concrete Cognito client over URLSession.
struct WhoopAuth: WhoopAuthing {
    private let endpoint = URL(string: "https://api.prod.whoop.com/auth-service/v3/whoop/")!

    /// The AWS Swift SDK user-agent the iOS app sends. Static app constant.
    private let cognitoUserAgent =
        "aws-sdk-swift/1.5.86 ua/2.1 api/cognito_identity_provider#1.5.86 os/ios#26.3.1 lang/swift#5.10 m/D,N,Z,b"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// USER_PASSWORD_AUTH login. Returns tokens, or an MFA challenge + session for the caller to
    /// answer via respondToMfa(). The password is used here and never stored or logged.
    func initiateAuth(email: String, password: String) async -> WhoopCognitoLoginResult {
        guard let resp = await callCognito(
            target: "InitiateAuth",
            body: [
                "AuthFlow": "USER_PASSWORD_AUTH",
                "AuthParameters": ["USERNAME": email, "PASSWORD": password],
                "ClientId": "",
            ]
        ) else { return .failed }

        if case .object = resp["AuthenticationResult"], let tokens = Self.tokens(from: resp["AuthenticationResult"]) {
            return .ok(tokens)
        }

        if let name = resp["ChallengeName"].stringValue,
           let challenge = WhoopMfaChallenge(rawValue: name),
           let session = resp["Session"].stringValue {
            return .mfa(challenge: challenge, session: session, username: email)
        }

        return .failed
    }

    /// Answer an MFA challenge from initiateAuth with the user's code. Returns tokens on
    /// success, or nil on a bad/expired code or any failure.
    func respondToMfa(
        challenge: WhoopMfaChallenge, session: String, username: String, code: String
    ) async -> WhoopCognitoTokens? {
        let resp = await callCognito(
            target: "RespondToAuthChallenge",
            body: [
                "ClientId": "",
                "ChallengeName": challenge.rawValue,
                "Session": session,
                "ChallengeResponses": [
                    "USERNAME": username,
                    challenge.codeField: code.trimmingCharacters(in: .whitespacesAndNewlines),
                ],
            ]
        )
        return Self.tokens(from: resp?["AuthenticationResult"] ?? .null)
    }

    /// REFRESH_TOKEN_AUTH: mint a fresh access token from the refresh token (no MFA). Cognito
    /// usually doesn't rotate the refresh token, so the returned `refreshToken` is typically nil
    /// and the caller keeps the existing one.
    func refreshTokens(refreshToken: String) async -> WhoopCognitoTokens? {
        let resp = await callCognito(
            target: "InitiateAuth",
            body: [
                "AuthFlow": "REFRESH_TOKEN_AUTH",
                "AuthParameters": ["REFRESH_TOKEN": refreshToken],
                "ClientId": "",
            ]
        )
        return Self.tokens(from: resp?["AuthenticationResult"] ?? .null)
    }

    /// POST one Cognito action through Whoop's proxy. Returns the parsed body, or nil on
    /// any transport/HTTP/parse failure (never throws, never logs the body).
    private func callCognito(target: String, body: [String: Any]) async -> JSONValue? {
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "content-type")
        request.setValue(
            "AWSCognitoIdentityProviderService.\(target)", forHTTPHeaderField: "x-amz-target")
        request.setValue("attempt=1; max=1", forHTTPHeaderField: "amz-sdk-request")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "amz-sdk-invocation-id")
        request.setValue(cognitoUserAgent, forHTTPHeaderField: "user-agent")
        request.setValue("*/*", forHTTPHeaderField: "accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "accept-language")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }

        let value = JSONValue.decode(data)
        return value.isObject ? value : nil
    }

    /// Build `WhoopCognitoTokens` from an AuthenticationResult node, or nil when it carries no
    /// AccessToken. Prefers the JWT's own `exp`, falling back to now + ExpiresIn if undecodable.
    private static func tokens(from auth: JSONValue) -> WhoopCognitoTokens? {
        guard let accessToken = auth["AccessToken"].stringValue else { return nil }
        let jwtExpMs = decodeJwtExpMs(accessToken)
        let expiresAt: Double
        if jwtExpMs > 0 {
            expiresAt = jwtExpMs
        } else {
            let expiresInSec = auth["ExpiresIn"].numberValue ?? 0
            expiresAt = Date().timeIntervalSince1970 * 1000 + expiresInSec * 1000
        }
        return WhoopCognitoTokens(
            accessToken: accessToken,
            refreshToken: auth["RefreshToken"].stringValue,
            expiresAt: expiresAt
        )
    }

    /// Pull the `exp` claim (epoch ms) out of a JWT, or 0 if it can't be read.
    private static func decodeJwtExpMs(_ jwt: String) -> Double {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, let json = decodeBase64Url(String(parts[1])) else { return 0 }
        let exp = JSONValue.decode(json)["exp"].numberValue
        return (exp ?? 0) * 1000
    }

    /// Base64url-decode to bytes, padding to a multiple of 4. nil on malformed input.
    private static func decodeBase64Url(_ input: String) -> Data? {
        var base64 = input.replacing("-", with: "+")
            .replacing("_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

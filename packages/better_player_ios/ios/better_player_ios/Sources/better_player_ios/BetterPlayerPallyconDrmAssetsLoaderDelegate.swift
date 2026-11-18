// Better Player Swift implementation

import AVFoundation
import Foundation

/// AVAssetResourceLoader delegate that handles FairPlay license requests for PallyCon.
/// `headers` must contain a `siteId`; every other entry is sent as an HTTP header
/// on the license request.
public class BetterPlayerPallyconDrmAssetsLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {

    public let certificateURL: URL
    public let licenseURL: URL?
    public let siteId: String
    public let requestHeaders: [String: String]

    private let defaultLicenseServerURL = URL(string: "https://license-global.pallycon.com/ri/licenseManager.do")!

    /// Returns nil when `headers` has no `siteId`.
    public init?(_ certificateURL: URL, withLicenseURL licenseURL: URL?, withHeaders headers: [AnyHashable: Any]) {
        var site: String?
        var others: [String: String] = [:]
        for (key, value) in headers {
            guard let k = key as? String, let v = value as? String else { continue }
            if k == "siteId" {
                site = v
            } else {
                others[k] = v
            }
        }
        guard let siteId = site else { return nil }
        self.certificateURL = certificateURL
        self.licenseURL = licenseURL
        self.siteId = siteId
        self.requestHeaders = others
        super.init()
    }

    private func pallyconError(_ code: Int, _ message: String) -> NSError {
        return NSError(
            domain: "BetterPlayerPallyCon",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    /// Blocking request. The resource loader calls this on its own serial queue.
    private func sendSynchronousRequest(_ request: URLRequest) -> (Data?, Error?) {
        var result: Data?
        var requestError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, error in
            result = data
            requestError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return (result, requestError)
    }

    private func decodedBody(_ body: Data?) -> Data? {
        guard let body = body, !body.isEmpty else { return nil }
        return Data(base64Encoded: body, options: .ignoreUnknownCharacters)
    }

    private func fetchCertificate() -> (Data?, Error?) {
        guard let url = URL(string: "\(certificateURL.absoluteString)?siteId=\(siteId)") else {
            return (nil, pallyconError(-3, "Invalid certificate URL"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (body, error) = sendSynchronousRequest(request)
        return (decodedBody(body), error)
    }

    private func fetchLicense(spc: Data) -> (Data?, Error?) {
        var request = URLRequest(url: licenseURL ?? defaultLicenseServerURL)
        request.httpMethod = "POST"
        request.httpBody = "spc=\(spc.base64EncodedString())".data(using: .utf8)
        for (key, value) in requestHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (body, error) = sendSynchronousRequest(request)
        return (decodedBody(body), error)
    }

    // MARK: - AVAssetResourceLoaderDelegate

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let assetURI = loadingRequest.request.url, assetURI.scheme == "skd" else {
            return false
        }

        let (certificate, certError) = fetchCertificate()
        guard let cert = certificate, !cert.isEmpty else {
            loadingRequest.finishLoading(with: certError ?? pallyconError(-1, "FairPlay certificate empty"))
            return true
        }

        let contentId = assetURI.absoluteString.data(using: .utf8) ?? Data()
        let spc: Data
        do {
            spc = try loadingRequest.streamingContentKeyRequestData(
                forApp: cert,
                contentIdentifier: contentId,
                options: nil
            )
        } catch {
            loadingRequest.finishLoading(with: error)
            return true
        }

        let (ckc, licenseError) = fetchLicense(spc: spc)
        if let ckc = ckc, !ckc.isEmpty {
            loadingRequest.dataRequest?.respond(with: ckc)
            loadingRequest.finishLoading()
        } else {
            loadingRequest.finishLoading(with: licenseError ?? pallyconError(-2, "Empty CKC / license failure"))
        }
        return true
    }

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
        return self.resourceLoader(resourceLoader, shouldWaitForLoadingOfRequestedResource: renewalRequest)
    }
}

// Better Player Swift implementation

import AVFoundation
import Foundation

/// AVAssetResourceLoader delegate that handles FairPlay license requests for Gumlet.
/// The Gumlet license server expects `{"spc": "<base64>"}` and answers `{"ckc": "<base64>"}`.
public class BetterPlayerGumletAssetsLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {

    public let certificateURL: URL
    public let licenseURL: URL?

    private let finishLock = NSLock()
    private var finishedRequests = Set<ObjectIdentifier>()

    public init(_ certificateURL: URL, withLicenseURL licenseURL: URL?) {
        self.certificateURL = certificateURL
        self.licenseURL = licenseURL
        super.init()
    }

    private func gumletError(_ code: Int, _ message: String) -> NSError {
        return NSError(
            domain: "BetterPlayerGumletFPS",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    /// Finishes a loading request at most once.
    private func finishOnce(_ request: AVAssetResourceLoadingRequest, ckc: Data?, error: Error?) {
        let id = ObjectIdentifier(request)
        finishLock.lock()
        let alreadyFinished = !finishedRequests.insert(id).inserted
        finishLock.unlock()
        if alreadyFinished { return }

        if let ckc = ckc {
            request.dataRequest?.respond(with: ckc)
            request.finishLoading()
        } else {
            request.finishLoading(with: error ?? gumletError(-1, "Unknown error"))
        }

        // Avoid unbounded growth of the bookkeeping set.
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self else { return }
            self.finishLock.lock()
            self.finishedRequests.remove(id)
            self.finishLock.unlock()
        }
    }

    private func requestCkc(spc: Data, loadingRequest: AVAssetResourceLoadingRequest) {
        guard let licenseURL = licenseURL else {
            finishOnce(loadingRequest, ckc: nil, error: gumletError(-3, "Missing license URL"))
            return
        }
        guard let body = try? JSONSerialization.data(withJSONObject: ["spc": spc.base64EncodedString()]) else {
            finishOnce(loadingRequest, ckc: nil, error: gumletError(-4, "Failed to encode SPC"))
            return
        }

        var request = URLRequest(url: licenseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                self.finishOnce(loadingRequest, ckc: nil, error: error)
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                self.finishOnce(loadingRequest, ckc: nil, error: self.gumletError(http.statusCode, "License server returned \(http.statusCode)"))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.finishOnce(loadingRequest, ckc: nil, error: self.gumletError(-10, "Invalid JSON from license server"))
                return
            }
            // Some providers use a different key; keep "license" as a fallback.
            let ckcString = (json["ckc"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (json["license"] as? String)
            guard let ckcB64 = ckcString, !ckcB64.isEmpty else {
                self.finishOnce(loadingRequest, ckc: nil, error: self.gumletError(-11, "Missing 'ckc' in license JSON"))
                return
            }
            guard let ckc = Data(base64Encoded: ckcB64) else {
                self.finishOnce(loadingRequest, ckc: nil, error: self.gumletError(-12, "Failed to decode CKC base64"))
                return
            }
            self.finishOnce(loadingRequest, ckc: ckc, error: nil)
        }.resume()
    }

    // MARK: - AVAssetResourceLoaderDelegate

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let assetURI = loadingRequest.request.url, assetURI.scheme == "skd" else {
            return false
        }

        guard let certificate = try? Data(contentsOf: certificateURL), !certificate.isEmpty else {
            loadingRequest.finishLoading(with: NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorClientCertificateRejected,
                userInfo: [NSLocalizedDescriptionKey: "Unable to load FairPlay certificate"]
            ))
            return true
        }

        let contentId = assetURI.absoluteString.data(using: .utf8) ?? Data()
        do {
            let spc = try loadingRequest.streamingContentKeyRequestData(
                forApp: certificate,
                contentIdentifier: contentId,
                options: nil
            )
            requestCkc(spc: spc, loadingRequest: loadingRequest)
        } catch {
            loadingRequest.finishLoading(with: error)
        }
        return true
    }

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
        return self.resourceLoader(resourceLoader, shouldWaitForLoadingOfRequestedResource: renewalRequest)
    }
}

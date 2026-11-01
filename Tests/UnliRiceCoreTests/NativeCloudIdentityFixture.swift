import Foundation
@testable import UnliRiceCore

struct NativeCloudIdentityFixture: NativeCloudIdentityProvider {
    var clientID = "test.client"
    var environment = "Development"
    var token: NSObject? = "token" as NSString
    var recordName = "record"
    var onLookup: (() throws -> Void)? = nil
    func currentUbiquityToken() -> NSObject? { token }
    func canonicalRecordName(isValid: @escaping () -> Bool) throws -> String {
        guard isValid() else { throw CancellationError() }
        try onLookup?()
        return recordName
    }
}

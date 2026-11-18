import Testing
@testable import MedyaCore

@Test func appIdentityIsEtodo() {
    #expect(AppIdentity.displayName == "Etodo")
    #expect(AppIdentity.folderName == "Etodo")
    #expect(AppIdentity.bundleID == "app.etodo.mac")
}

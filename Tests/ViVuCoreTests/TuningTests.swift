import Testing
@testable import ViVuCore

@Suite struct TuningTests {
    @Test func bundleIDMatchesInfoPlist() {
        // Scripts/bundle.sh writes the same identifier into Info.plist.
        #expect(Tuning.bundleID == "app.vivuview.ViVuView")
    }

    @Test func signpostIDsAreUsable() {
        let id = Signposts.decode.makeSignpostID()
        let state = Signposts.decode.beginInterval("Decode", id: id)
        Signposts.decode.endInterval("Decode", state)
    }
}

import Testing
@testable import MuniMetadonneesCore

struct MuniMetadonneesCoreTests {
    @Test
    func placeholderReturnsNotImplementedStatus() {
        let request = ToolRequest(requestID: "req-1", tool: "MuniMetadonnees", action: "run")
        let result = MuniMetadonneesRunner.runPlaceholder(request: request)

        #expect(result.status == ToolStatus.notImplemented)
        #expect(result.errors.first?.code == "NOT_IMPLEMENTED")
        #expect(result.requestID == "req-1")
    }
}

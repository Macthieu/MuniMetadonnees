import Foundation

public enum MuniMetadonneesRunner {
    public static func runPlaceholder(request: ToolRequest) -> ToolResult {
        let now = ISO8601DateFormatter().string(from: Date())

        return ToolResult(
            requestID: request.requestID,
            tool: "MuniMetadonnees",
            status: .notImplemented,
            startedAt: now,
            finishedAt: now,
            progressEvents: [
                ProgressEvent(
                    requestID: request.requestID,
                    status: .notImplemented,
                    stage: "bootstrap",
                    percent: 100,
                    message: "MuniMetadonnees scaffold is ready; business logic not implemented.",
                    occurredAt: now
                )
            ],
            outputArtifacts: [],
            errors: [
                ToolError(
                    code: "NOT_IMPLEMENTED",
                    message: "MuniMetadonnees is scaffolded for CLI JSON V1 but processing logic is not implemented yet.",
                    retryable: false
                )
            ],
            summary: "MuniMetadonnees returned a placeholder not_implemented result."
        )
    }
}

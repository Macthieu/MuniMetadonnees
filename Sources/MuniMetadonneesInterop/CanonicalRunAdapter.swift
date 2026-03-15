import Foundation
import MuniMetadonneesCore
import OrchivisteKitContracts

private struct AnalysisReportTerm: Codable {
    let term: String
    let occurrences: Int
}

private struct AnalysisReportPayload: Codable {
    let preview: String?
    let topTerms: [AnalysisReportTerm]?

    enum CodingKeys: String, CodingKey {
        case preview
        case topTerms = "top_terms"
    }
}

public enum CanonicalRunAdapterError: Error, Sendable {
    case unsupportedAction(String)
    case missingInput
    case invalidParameter(String, String)
    case sourceReadFailed(String)
    case analysisReportParseFailed(String)
    case reportWriteFailed(String)
    case runtimeFailure(String)

    var toolError: ToolError {
        switch self {
        case .unsupportedAction(let action):
            return ToolError(code: "UNSUPPORTED_ACTION", message: "Unsupported action: \(action)", retryable: false)
        case .missingInput:
            return ToolError(
                code: "MISSING_INPUT",
                message: "Provide metadata input via text/source_path/input artifact or analysis_report_path.",
                retryable: false
            )
        case .invalidParameter(let parameter, let reason):
            return ToolError(code: "INVALID_PARAMETER", message: "Invalid parameter \(parameter): \(reason)", retryable: false)
        case .sourceReadFailed(let reason):
            return ToolError(code: "SOURCE_READ_FAILED", message: reason, retryable: false)
        case .analysisReportParseFailed(let reason):
            return ToolError(code: "ANALYSIS_REPORT_PARSE_FAILED", message: reason, retryable: false)
        case .reportWriteFailed(let reason):
            return ToolError(code: "REPORT_WRITE_FAILED", message: reason, retryable: true)
        case .runtimeFailure(let reason):
            return ToolError(code: "RUNTIME_FAILURE", message: reason, retryable: false)
        }
    }
}

private struct CanonicalExecutionContext: Sendable {
    let input: MetadataEnrichmentInput
    let outputPath: String?
}

private struct ParsedAnalysisSeed: Sendable {
    let previewText: String?
    let seedTerms: [MetadataSeedTerm]
}

public enum CanonicalRunAdapter {
    public static func execute(request: ToolRequest) -> ToolResult {
        let startedAt = isoTimestamp()

        do {
            let context = try parseContext(from: request)
            let report = MuniMetadonneesRunner.enrich(input: context.input, generatedAt: isoTimestamp())
            let status: ToolStatus = report.warnings.isEmpty ? .succeeded : .needsReview
            let finishedAt = isoTimestamp()

            var artifacts: [ArtifactDescriptor] = []
            if let outputPath = context.outputPath {
                try writeReport(report, toPath: outputPath)
                artifacts.append(
                    ArtifactDescriptor(
                        id: "metadata_report",
                        kind: .report,
                        uri: fileURI(forPath: outputPath),
                        mediaType: "application/json",
                        metadata: [
                            "keyword_count": .number(Double(report.keywordCount)),
                            "analysis_seed_count": .number(Double(report.analysisSeedCount))
                        ]
                    )
                )
            }

            let summary = report.warnings.isEmpty
                ? "Metadata enrichment completed successfully."
                : "Metadata enrichment completed with review warnings."

            return makeResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                status: status,
                summary: summary,
                outputArtifacts: artifacts,
                errors: [],
                metadata: resultMetadata(from: report)
            )
        } catch let adapterError as CanonicalRunAdapterError {
            let finishedAt = isoTimestamp()
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: [adapterError.toolError],
                summary: "Canonical metadata request failed."
            )
        } catch {
            let finishedAt = isoTimestamp()
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: [CanonicalRunAdapterError.runtimeFailure(error.localizedDescription).toolError],
                summary: "Canonical metadata request failed with an unexpected runtime error."
            )
        }
    }

    private static func parseContext(from request: ToolRequest) throws -> CanonicalExecutionContext {
        try validateAction(request.action)

        let inlineText = try optionalStringParameter("text", in: request)
        let sourcePath = try optionalStringParameter("source_path", in: request)
        let outputPath = try optionalStringParameter("metadata_output_path", in: request)

        let maxKeywords = try optionalIntParameter("max_keywords", in: request) ?? 10
        guard (1...30).contains(maxKeywords) else {
            throw CanonicalRunAdapterError.invalidParameter("max_keywords", "expected integer in range 1...30")
        }

        let summarySentenceCount = try optionalIntParameter("summary_sentence_count", in: request) ?? 2
        guard (1...5).contains(summarySentenceCount) else {
            throw CanonicalRunAdapterError.invalidParameter("summary_sentence_count", "expected integer in range 1...5")
        }

        let parsedAnalysis = try resolveAnalysisSeed(from: request)

        let resolvedText: String
        let sourceKind: String

        if let inlineText, !inlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedText = inlineText
            sourceKind = "inline_text"
        } else if let sourcePath {
            resolvedText = try readText(fromPath: sourcePath)
            sourceKind = "source_path"
        } else if let artifactPath = firstInputArtifactPath(in: request) {
            resolvedText = try readText(fromPath: artifactPath)
            sourceKind = "input_artifact"
        } else if let preview = parsedAnalysis.previewText,
                  !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedText = preview
            sourceKind = "analysis_report_preview"
        } else {
            resolvedText = ""
            sourceKind = parsedAnalysis.seedTerms.isEmpty ? "unknown" : "analysis_report"
        }

        if resolvedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedAnalysis.seedTerms.isEmpty {
            throw CanonicalRunAdapterError.missingInput
        }

        return CanonicalExecutionContext(
            input: MetadataEnrichmentInput(
                text: resolvedText,
                sourceKind: sourceKind,
                seedTerms: parsedAnalysis.seedTerms,
                maxKeywords: maxKeywords,
                summarySentenceCount: summarySentenceCount
            ),
            outputPath: outputPath
        )
    }

    private static func validateAction(_ rawAction: String) throws {
        let normalized = rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "run", "enrich":
            return
        default:
            throw CanonicalRunAdapterError.unsupportedAction(rawAction)
        }
    }

    private static func optionalStringParameter(_ key: String, in request: ToolRequest) throws -> String? {
        guard let value = request.parameters[key] else {
            return nil
        }
        switch value {
        case .string(let rawValue):
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return ""
            }
            switch key {
            case "source_path", "analysis_report_path", "metadata_output_path":
                return resolvePathFromURIOrPath(trimmed)
            default:
                return trimmed
            }
        default:
            throw CanonicalRunAdapterError.invalidParameter(key, "expected string")
        }
    }

    private static func optionalIntParameter(_ key: String, in request: ToolRequest) throws -> Int? {
        guard let value = request.parameters[key] else {
            return nil
        }
        switch value {
        case .number(let numberValue):
            guard numberValue.rounded() == numberValue else {
                throw CanonicalRunAdapterError.invalidParameter(key, "expected integer value")
            }
            return Int(numberValue)
        default:
            throw CanonicalRunAdapterError.invalidParameter(key, "expected number")
        }
    }

    private static func resolveAnalysisSeed(from request: ToolRequest) throws -> ParsedAnalysisSeed {
        if let explicitPath = try optionalStringParameter("analysis_report_path", in: request), !explicitPath.isEmpty {
            return try parseAnalysisSeed(fromPath: explicitPath)
        }

        if let reportArtifact = request.inputArtifacts.first(where: { $0.kind == .report }) {
            return try parseAnalysisSeed(fromPath: resolvePathFromURIOrPath(reportArtifact.uri))
        }

        return ParsedAnalysisSeed(previewText: nil, seedTerms: [])
    }

    private static func parseAnalysisSeed(fromPath path: String) throws -> ParsedAnalysisSeed {
        let fileURL = URL(fileURLWithPath: path)
        let data: Data

        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CanonicalRunAdapterError.sourceReadFailed(
                "Unable to read analysis report at \(path): \(error.localizedDescription)"
            )
        }

        if let payload = try? JSONDecoder().decode(AnalysisReportPayload.self, from: data) {
            let seedTerms = (payload.topTerms ?? []).map { MetadataSeedTerm(term: $0.term, occurrences: $0.occurrences) }
            return ParsedAnalysisSeed(previewText: payload.preview, seedTerms: seedTerms)
        }

        if let toolResult = try? JSONDecoder().decode(ToolResult.self, from: data) {
            return ParsedAnalysisSeed(
                previewText: jsonString(from: toolResult.metadata["preview"]),
                seedTerms: parseSeedTerms(fromToolMetadata: toolResult.metadata)
            )
        }

        throw CanonicalRunAdapterError.analysisReportParseFailed(
            "Unsupported JSON structure for analysis report at \(path)."
        )
    }

    private static func parseSeedTerms(fromToolMetadata metadata: [String: JSONValue]) -> [MetadataSeedTerm] {
        guard case .array(let entries)? = metadata["top_terms"] else {
            return []
        }

        return entries.compactMap { value in
            guard case .object(let object) = value,
                  let term = jsonString(from: object["term"]),
                  let occurrences = jsonInt(from: object["occurrences"]) else {
                return nil
            }
            return MetadataSeedTerm(term: term, occurrences: occurrences)
        }
    }

    private static func jsonString(from value: JSONValue?) -> String? {
        guard case .string(let raw)? = value else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func jsonInt(from value: JSONValue?) -> Int? {
        guard case .number(let raw)? = value else {
            return nil
        }
        guard raw.rounded() == raw else {
            return nil
        }
        return Int(raw)
    }

    private static func firstInputArtifactPath(in request: ToolRequest) -> String? {
        request.inputArtifacts
            .first(where: { $0.kind == .input })
            .map { resolvePathFromURIOrPath($0.uri) }
    }

    private static func readText(fromPath path: String) throws -> String {
        let fileURL = URL(fileURLWithPath: path)

        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            do {
                let data = try Data(contentsOf: fileURL)
                return String(decoding: data, as: UTF8.self)
            } catch {
                throw CanonicalRunAdapterError.sourceReadFailed(
                    "Unable to read source text at \(path): \(error.localizedDescription)"
                )
            }
        }
    }

    private static func writeReport(_ report: MetadataEnrichmentReport, toPath path: String) throws {
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(report)
            try data.write(to: url, options: .atomic)
        } catch {
            throw CanonicalRunAdapterError.reportWriteFailed(
                "Unable to write metadata report at \(path): \(error.localizedDescription)"
            )
        }
    }

    private static func resultMetadata(from report: MetadataEnrichmentReport) -> [String: JSONValue] {
        var metadata: [String: JSONValue] = [
            "source_kind": .string(report.sourceKind),
            "keyword_count": .number(Double(report.keywordCount)),
            "summary": .string(report.summary),
            "suggested_title": .string(report.suggestedTitle),
            "analysis_seed_count": .number(Double(report.analysisSeedCount)),
            "keywords": .array(
                report.keywords.map {
                    .object([
                        "term": .string($0.term),
                        "score": .number(Double($0.score))
                    ])
                }
            )
        ]

        if !report.warnings.isEmpty {
            metadata["warnings"] = .array(report.warnings.map { .string($0) })
        }

        return metadata
    }

    private static func makeResult(
        request: ToolRequest,
        startedAt: String,
        finishedAt: String,
        status: ToolStatus,
        summary: String,
        outputArtifacts: [ArtifactDescriptor],
        errors: [ToolError],
        metadata: [String: JSONValue]
    ) -> ToolResult {
        ToolResult(
            requestID: request.requestID,
            tool: request.tool,
            status: status,
            startedAt: startedAt,
            finishedAt: finishedAt,
            progressEvents: [
                ProgressEvent(
                    requestID: request.requestID,
                    status: .running,
                    stage: "load_input",
                    percent: 20,
                    message: "Canonical request parsed.",
                    occurredAt: startedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: .running,
                    stage: "enrich_metadata",
                    percent: 75,
                    message: "Deterministic metadata enrichment executed.",
                    occurredAt: finishedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: status,
                    stage: "metadata_complete",
                    percent: 100,
                    message: summary,
                    occurredAt: finishedAt
                )
            ],
            outputArtifacts: outputArtifacts,
            errors: errors,
            summary: summary,
            metadata: metadata
        )
    }

    private static func makeFailureResult(
        request: ToolRequest,
        startedAt: String,
        finishedAt: String,
        errors: [ToolError],
        summary: String
    ) -> ToolResult {
        ToolResult(
            requestID: request.requestID,
            tool: request.tool,
            status: .failed,
            startedAt: startedAt,
            finishedAt: finishedAt,
            progressEvents: [
                ProgressEvent(
                    requestID: request.requestID,
                    status: .running,
                    stage: "load_input",
                    percent: 20,
                    message: "Canonical request parsed.",
                    occurredAt: startedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: .failed,
                    stage: "metadata_failed",
                    percent: 100,
                    message: summary,
                    occurredAt: finishedAt
                )
            ],
            outputArtifacts: [],
            errors: errors,
            summary: summary,
            metadata: ["action": .string(request.action)]
        )
    }

    private static func resolvePathFromURIOrPath(_ candidate: String) -> String {
        guard let url = URL(string: candidate), url.isFileURL else {
            return candidate
        }
        return url.path
    }

    private static func fileURI(forPath path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

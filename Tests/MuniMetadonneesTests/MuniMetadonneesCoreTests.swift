import Foundation
import OrchivisteKitContracts
import Testing
@testable import MuniMetadonneesCore
@testable import MuniMetadonneesInterop

struct MuniMetadonneesCoreTests {
    @Test
    func enrichIsDeterministicForSameInput() {
        let input = MetadataEnrichmentInput(
            text: "Budget municipal 2026 adopte en seance publique. Budget revise.",
            sourceKind: "inline_text",
            seedTerms: [MetadataSeedTerm(term: "budget", occurrences: 3)],
            maxKeywords: 5,
            summarySentenceCount: 2
        )

        let first = MuniMetadonneesRunner.enrich(input: input, generatedAt: "2026-03-15T00:00:00Z")
        let second = MuniMetadonneesRunner.enrich(input: input, generatedAt: "2026-03-15T00:00:00Z")

        #expect(first == second)
        #expect(first.keywords.first?.term == "budget")
        #expect(first.keywordCount > 0)
        #expect(!first.summary.isEmpty)
    }

    @Test
    func canonicalRunWithInlineTextSucceeds() {
        let request = ToolRequest(
            requestID: "req-inline",
            tool: "MuniMetadonnees",
            action: "run",
            parameters: [
                "text": .string("Resolution municipale sur la voirie locale et l'entretien hivernal."),
                "max_keywords": .number(8),
                "summary_sentence_count": .number(2)
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .succeeded)
        #expect(result.errors.isEmpty)
        #expect(result.progressEvents.last?.status == .succeeded)
    }

    @Test
    func canonicalRunWithShortTextReturnsNeedsReview() {
        let request = ToolRequest(
            requestID: "req-short",
            tool: "MuniMetadonnees",
            action: "run",
            parameters: [
                "text": .string("OK")
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .needsReview)
        #expect(result.errors.isEmpty)
        #expect(result.progressEvents.last?.status == .needsReview)
    }

    @Test
    func canonicalRunUsesMuniAnalyseReportAsSeed() throws {
        let tempDirectory = try makeTempDirectory(prefix: "muni-metadonnees-report-seed")
        let analysisReportPath = tempDirectory.appendingPathComponent("analysis-report.json").path

        let analysisPayload = """
        {
          "generated_at": "2026-03-15T11:00:00Z",
          "preview": "Compte rendu municipal sur le budget 2026 et les investissements.",
          "top_terms": [
            {"term": "budget", "occurrences": 5},
            {"term": "investissements", "occurrences": 3},
            {"term": "municipal", "occurrences": 2}
          ]
        }
        """
        try analysisPayload.write(toFile: analysisReportPath, atomically: true, encoding: .utf8)

        let request = ToolRequest(
            requestID: "req-analysis-seed",
            tool: "MuniMetadonnees",
            action: "run",
            parameters: [
                "analysis_report_path": .string(analysisReportPath)
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .succeeded || result.status == .needsReview)
        #expect(result.errors.isEmpty)
        #expect(result.metadata["analysis_seed_count"] != nil)
    }

    @Test
    func canonicalRunFailsWithoutAnyInput() {
        let request = ToolRequest(
            requestID: "req-missing",
            tool: "MuniMetadonnees",
            action: "run"
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .failed)
        #expect(result.errors.first?.code == "MISSING_INPUT")
    }

    @Test
    func canonicalRunWritesMetadataReportArtifact() throws {
        let tempDirectory = try makeTempDirectory(prefix: "muni-metadonnees-report-output")
        let outputPath = tempDirectory.appendingPathComponent("metadata-report.json").path

        let request = ToolRequest(
            requestID: "req-output",
            tool: "MuniMetadonnees",
            action: "run",
            parameters: [
                "text": .string("Analyse locale des routes, trottoirs et priorites de maintenance."),
                "metadata_output_path": .string(outputPath)
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .succeeded)
        #expect(result.outputArtifacts.count == 1)
        #expect(result.outputArtifacts.first?.kind == .report)
        #expect(FileManager.default.fileExists(atPath: outputPath))
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}

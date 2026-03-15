import Foundation

public struct MetadataSeedTerm: Codable, Equatable, Sendable {
    public let term: String
    public let occurrences: Int

    public init(term: String, occurrences: Int) {
        self.term = term
        self.occurrences = max(1, occurrences)
    }
}

public struct MetadataKeyword: Codable, Equatable, Sendable {
    public let term: String
    public let score: Int

    public init(term: String, score: Int) {
        self.term = term
        self.score = max(1, score)
    }
}

public struct MetadataEnrichmentInput: Equatable, Sendable {
    public let text: String
    public let sourceKind: String
    public let seedTerms: [MetadataSeedTerm]
    public let maxKeywords: Int
    public let summarySentenceCount: Int

    public init(
        text: String,
        sourceKind: String,
        seedTerms: [MetadataSeedTerm] = [],
        maxKeywords: Int = 10,
        summarySentenceCount: Int = 2
    ) {
        self.text = text
        self.sourceKind = sourceKind
        self.seedTerms = seedTerms
        self.maxKeywords = max(1, maxKeywords)
        self.summarySentenceCount = max(1, summarySentenceCount)
    }
}

public struct MetadataEnrichmentReport: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let sourceKind: String
    public let keywordCount: Int
    public let keywords: [MetadataKeyword]
    public let summary: String
    public let suggestedTitle: String
    public let analysisSeedCount: Int
    public let warnings: [String]

    public init(
        generatedAt: String,
        sourceKind: String,
        keywordCount: Int,
        keywords: [MetadataKeyword],
        summary: String,
        suggestedTitle: String,
        analysisSeedCount: Int,
        warnings: [String]
    ) {
        self.generatedAt = generatedAt
        self.sourceKind = sourceKind
        self.keywordCount = keywordCount
        self.keywords = keywords
        self.summary = summary
        self.suggestedTitle = suggestedTitle
        self.analysisSeedCount = analysisSeedCount
        self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case sourceKind = "source_kind"
        case keywordCount = "keyword_count"
        case keywords
        case summary
        case suggestedTitle = "suggested_title"
        case analysisSeedCount = "analysis_seed_count"
        case warnings
    }
}

public enum MuniMetadonneesRunner {
    private static let stopWords: Set<String> = [
        "a", "an", "and", "au", "aux", "avec", "ce", "ces", "cette", "dans", "de", "des",
        "du", "en", "est", "et", "for", "il", "is", "la", "le", "les", "mais", "ou", "par",
        "pour", "sur", "the", "to", "un", "une"
    ]

    public static func enrich(
        input: MetadataEnrichmentInput,
        generatedAt: String? = nil
    ) -> MetadataEnrichmentReport {
        let timestamp = generatedAt ?? isoTimestamp()
        let normalizedText = input.text.trimmingCharacters(in: .whitespacesAndNewlines)

        var frequencies = termFrequencies(from: normalizedText)
        for seedTerm in input.seedTerms {
            let normalizedTerm = normalizeTerm(seedTerm.term)
            guard !normalizedTerm.isEmpty else { continue }
            frequencies[normalizedTerm, default: 0] += max(1, seedTerm.occurrences)
        }

        let keywords = frequencies
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(input.maxKeywords)
            .map { MetadataKeyword(term: $0.key, score: $0.value) }

        var summary = buildSummary(from: normalizedText, sentenceCount: input.summarySentenceCount)
        if summary.isEmpty, !keywords.isEmpty {
            let fallbackTerms = keywords.prefix(5).map(\ .term).joined(separator: ", ")
            summary = "Mots-cles identifies: \(fallbackTerms)."
        }

        let suggestedTitle = buildSuggestedTitle(keywords: keywords, summary: summary)

        var warnings: [String] = []
        if normalizedText.isEmpty {
            warnings.append("Texte source absent; enrichissement base sur les donnees disponibles.")
        }
        if keywords.count < 3 {
            warnings.append("Peu de mots-cles fiables detectes; validation humaine recommandee.")
        }
        if summary.isEmpty {
            warnings.append("Resume non disponible.")
        }

        return MetadataEnrichmentReport(
            generatedAt: timestamp,
            sourceKind: input.sourceKind,
            keywordCount: keywords.count,
            keywords: keywords,
            summary: summary,
            suggestedTitle: suggestedTitle,
            analysisSeedCount: input.seedTerms.count,
            warnings: warnings
        )
    }

    private static func termFrequencies(from text: String) -> [String: Int] {
        let tokens = tokenize(text: text)
        var frequencies: [String: Int] = [:]

        for token in tokens where !stopWords.contains(token) && !isNumericToken(token) {
            frequencies[token, default: 0] += 1
        }

        return frequencies
    }

    private static func tokenize(text: String) -> [String] {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func normalizeTerm(_ term: String) -> String {
        term
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func buildSummary(from text: String, sentenceCount: Int) -> String {
        guard !text.isEmpty else {
            return ""
        }

        let sentences = text
            .split(whereSeparator: { ".!?".contains($0) })
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            }
            .filter { !$0.isEmpty }

        guard !sentences.isEmpty else {
            return String(text.prefix(220))
        }

        let selected = sentences.prefix(max(1, sentenceCount)).joined(separator: ". ")
        return selected + (selected.hasSuffix(".") ? "" : ".")
    }

    private static func buildSuggestedTitle(keywords: [MetadataKeyword], summary: String) -> String {
        if !keywords.isEmpty {
            let base = keywords.prefix(3).map { capitalize($0.term) }.joined(separator: " - ")
            if !base.isEmpty {
                return base
            }
        }

        let tokens = summary
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { !$0.isEmpty }

        if !tokens.isEmpty {
            return tokens.prefix(6).map(capitalize).joined(separator: " ")
        }

        return "Enrichissement Metadonnees"
    }

    private static func capitalize(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
    }

    private static func isNumericToken(_ token: String) -> Bool {
        !token.isEmpty && token.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

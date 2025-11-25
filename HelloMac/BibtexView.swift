//
//  BibtexView.swift
//  HelloMac
//

import SwiftUI
import AppKit
import Foundation

struct BibtexView: View {
    @State private var identifier: String = ""
    @State private var status: String?
    @State private var isLoading: Bool = false
    @State private var copied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Top bar with small red Quit button
            HStack {
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Circle()
                        .frame(width: 10, height: 10)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)

                Spacer()
            }

            Text("BibTeX from ID")
                .font(.headline)

            Text("Enter DOI, PMCID/PMID, arXiv ID, or a full reference:")
                .font(.subheadline)

            TextField("e.g. 10.1038/nphys1170, PMC1234567, 2101.00001, ...", text: $identifier)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()

                Button {
                    Task {
                        await fetchAndCopyBibtex()
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            copied ? "Copied!" : "Copy BibTeX",
                            systemImage: "doc.on.doc"
                        )
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(identifier.trimmed.isEmpty || isLoading)
            }

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }

            Spacer()
        }
        .onChange(of: identifier) { _ in
            copied = false
            status = nil
        }
    }

    // MARK: - Actions

    private func fetchAndCopyBibtex() async {
        let id = identifier.trimmed
        guard !id.isEmpty else { return }

        isLoading = true
        status = "Fetching BibTeX…"
        copied = false

        do {
            // First: try “direct ID” pipeline (DOI / PMID / PMCID / arXiv)
            let bibtex = try await fetchBibtex(for: id)
            let formatted = formatBibtexForClipboard(bibtex)
            copyToClipboard(formatted)
            status = "Copied BibTeX to clipboard"
            copied = true
        } catch let error as CitationError {
            switch error {
            case .unknownIdentifier:
                // Fallback 1: CrossRef search using the whole string as a query
                do {
                    let hit = try await searchCrossrefForDOI(query: id)
                    let bibtex = try await fetchBibtexFromDOI(hit.doi)
                    let formatted = formatBibtexForClipboard(bibtex)
                    copyToClipboard(formatted)

                    if let title = hit.title, let year = hit.year {
                        status = """
                        Copied BibTeX (resolved via CrossRef search: “\(title)” \(year); may not be exact!)
                        """
                    } else {
                        status = "Copied BibTeX (resolved via CrossRef search; may not be exact!)"
                    }

                    copied = true
                } catch {
                    // Fallback 2: heuristic DOI extraction from the text (Algo 2-style)
                    if let doi = extractDOIFromFreeText(id) {
                        do {
                            let bibtex = try await fetchBibtexFromDOI(doi)
                            let formatted = formatBibtexForClipboard(bibtex)
                            copyToClipboard(formatted)
                            status = """
                            Copied BibTeX (DOI heuristically extracted from text: \(doi); please double-check!!)
                            """
                            copied = true
                        } catch {
                            status = """
                            Tried CrossRef search and heuristic DOI extraction but couldn’t fetch a valid BibTeX entry.
                            (\(error.localizedDescription))
                            """
                        }
                    } else {
                        status = """
                        Couldn’t recognize this as a DOI, PMCID/PMID, or arXiv ID,
                        and CrossRef search / DOI extraction didn’t find anything.
                        """
                    }
                }

            default:
                status = error.errorDescription
            }
        } catch {
            status = "Unexpected error: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

// MARK: - Clipboard

private func copyToClipboard(_ string: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(string, forType: .string)
}

// MARK: - Helpers & models

private enum IdentifierType {
    case doi(String)
    case pmidOrPmc(String)
    case arxiv(String)
}

// Wrap pretty-formatting + LaTeX accent escaping in one place
private func formatBibtexForClipboard(_ raw: String) -> String {
    let pretty = prettyFormatBibtex(raw)
    let escaped = replaceLatexAccents(pretty)
    return escaped
}

private func prettyFormatBibtex(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    // If it doesn't start with @something{ and contain commas, skip formatting
    guard trimmed.first == "@", trimmed.contains("{"), trimmed.contains(",") else {
        return raw
    }

    // Split entry header from body
    guard let openBraceIndex = trimmed.firstIndex(of: "{") else { return raw }
    let header = String(trimmed[..<openBraceIndex]) + "{"

    // Remove header and final "}"
    var body = trimmed[openBraceIndex...]
        .dropFirst()   // remove "{"
        .dropLast()    // remove "}"
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // Split fields by comma that ends a line
    // But keep commas that appear inside braces { ... }
    var fields: [String] = []
    var current = ""
    var depth = 0   // track nesting like { ... }

    for char in body {
        if char == "{" { depth += 1 }
        if char == "}" { depth -= 1 }

        if char == "," && depth == 0 {
            fields.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
            current = ""
        } else {
            current.append(char)
        }
    }

    if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        fields.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // Now format nicely
    var output = "\(header)\n"

    for field in fields {
        if field.isEmpty { continue }
        output += "  \(field),\n"
    }

    output += "}"

    return output
}

// MARK: - LaTeX accent replacement (Unicode → LaTeX macros)

/// A conservative subset of the Python latexAccents map.
/// We avoid touching backslashes / braces, since the BibTeX may already contain TeX macros.
private let latexAccents: [Character: String] = [
    // Grave
    "à": "\\`a", "è": "\\`e", "ì": "\\`\\i{}", "ò": "\\`o", "ù": "\\`u", "ỳ": "\\`y",
    "À": "\\`A", "È": "\\`E", "Ì": "\\`I", "Ò": "\\`O", "Ù": "\\`U", "Ỳ": "\\`Y",

    // Acute
    "á": "\\'a", "ć": "\\'c", "é": "\\'e", "í": "\\'\\i{}", "ó": "\\'o", "ú": "\\'u", "ý": "\\'y",
    "Á": "\\'A", "É": "\\'E", "Í": "\\'I", "Ó": "\\'O", "Ú": "\\'U", "Ý": "\\'Y",

    // Circumflex
    "â": "\\^a", "ê": "\\^e", "î": "\\^\\i{}", "ô": "\\^o", "û": "\\^u", "ŷ": "\\^y",
    "Â": "\\^A", "Ê": "\\^E", "Î": "\\^I", "Ô": "\\^O", "Û": "\\^U", "Ŷ": "\\^Y",

    // Umlaut / dieresis
    "ä": "\\\"a", "ë": "\\\"e", "ï": "\\\"\\i{}", "ö": "\\\"o", "ü": "\\\"u", "ÿ": "\\\"y",
    "Ä": "\\\"A", "Ë": "\\\"E", "Ï": "\\\"I", "Ö": "\\\"O", "Ü": "\\\"U", "Ÿ": "\\\"Y",

    // Tilde / misc
    "ã": "\\~a", "ñ": "\\~n",
    "ç": "\\c{c}", "Ç": "\\c{C}",
    "œ": "{\\oe}", "Œ": "{\\OE}",
    "æ": "{\\ae}", "Æ": "{\\AE}",
    "å": "{\\aa}", "Å": "{\\AA}",
    "ø": "{\\o}",  "Ø": "{\\O}",
    "ß": "{\\ss}",

    // Dashes
    "–": "--", "—": "---", "−": "--",

    // Common typographic quotes
    "‘": "`",  "’": "'",  "“": "``", "”": "''",
    "‚": ",", "„": ",,",

    // Some Greek letters (math mode)
    "α": "$\\alpha$", "β": "$\\beta$", "γ": "$\\gamma$", "δ": "$\\delta$",
    "ε": "$\\epsilon$", "η": "$\\eta$", "θ": "$\\theta$", "λ": "$\\lambda$",
    "µ": "$\\mu$", "ν": "$\\nu$", "π": "$\\pi$", "σ": "$\\sigma$",
    "τ": "$\\tau$", "φ": "$\\phi$", "χ": "$\\chi$", "ψ": "$\\psi$", "ω": "$\\omega$",

    // Misc
    "°": "$^\\circ$",
    "\u{00A0}": " " // non-breaking space → normal space
]

private func replaceLatexAccents(_ string: String) -> String {
    let normalized = string.precomposedStringWithCanonicalMapping
    var result = ""
    result.reserveCapacity(normalized.count)

    for ch in normalized {
        if let replacement = latexAccents[ch] {
            result.append(replacement)
        } else {
            result.append(ch)
        }
    }

    return result
}

private enum CitationError: LocalizedError {
    case unknownIdentifier
    case notFound
    case invalidResponse
    case networkError(Int?)
    case missingDOI

    var errorDescription: String? {
        switch self {
        case .unknownIdentifier:
            return "Couldn’t recognize this as a DOI, PMCID/PMID, or arXiv ID."
        case .notFound:
            return "No record found for this ID."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .networkError(let code):
            if let code {
                return "Network error (status \(code))."
            } else {
                return "Network error."
            }
        case .missingDOI:
            return "Couldn’t find a DOI for this ID."
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - ID normalization & classification

/// Normalize DOI-like input: strip URL/prefix if present (https://doi.org/, dx.doi.org, doi:, etc.).
private func normalizeDOIPrefix(_ value: String) -> String {
    let trimmed = value.trimmed
    let lower = trimmed.lowercased()

    let prefixes = [
        "https://doi.org/",
        "http://doi.org/",
        "doi.org/",
        "https://dx.doi.org/",
        "http://dx.doi.org/",
        "dx.doi.org/",
        "doi:"
    ]

    for prefix in prefixes {
        if lower.hasPrefix(prefix) {
            let index = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            return String(trimmed[index...]).trimmed
        }
    }

    return trimmed
}

private func normalizePMIDorPMCID(_ value: String) -> String {
    let trimmed = value.trimmed
    let lower = trimmed.lowercased()

    if lower.hasPrefix("pmid:") {
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 5)
        return String(trimmed[idx...]).trimmed
    }

    if lower.hasPrefix("pmcid:") {
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 6)
        return String(trimmed[idx...]).trimmed
    }

    return trimmed
}

private func normalizeArxivID(_ value: String) -> String {
    let trimmed = value.trimmed
    let lower = trimmed.lowercased()

    if lower.hasPrefix("arxiv:") {
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 6)
        return String(trimmed[idx...]).trimmed
    }

    return trimmed
}

private func detectIdentifierType(for id: String) -> IdentifierType? {
    let trimmed = id.trimmed

    // DOI (with URL/prefix normalization)
    let normalizedDOI = normalizeDOIPrefix(trimmed)
    if normalizedDOI.range(of: #"^10\..+/.+$"#, options: .regularExpression) != nil {
        return .doi(normalizedDOI)
    }

    // PMID / PMCID (with optional prefixes)
    let normalizedPM = normalizePMIDorPMCID(trimmed)
    if normalizedPM.range(of: #"^\d+$|^PMC\d+(\.\d+)?$"#, options: .regularExpression) != nil {
        return .pmidOrPmc(normalizedPM)
    }

    // arXiv (new-style and old-style, with optional "arXiv:" prefix)
    let normalizedArxiv = normalizeArxivID(trimmed)

    // New style, e.g. 2101.00001 or 2101.00001v2
    if normalizedArxiv.range(of: #"^\d{4}\.\d{4,5}(v\d+)?$"#, options: .regularExpression) != nil {
        return .arxiv(normalizedArxiv)
    }

    // Old style, e.g. hep-th/0501234 or cond-mat/0601001
    if normalizedArxiv.range(of: #"^[a-z\-]+(\.[A-Z]{2})?/\d{7}(v\d+)?$"#, options: .regularExpression) != nil {
        return .arxiv(normalizedArxiv)
    }

    return nil
}

// MARK: - Networking

/// Main resolver: ID → (maybe) DOI → BibTeX via doi.org
private func fetchBibtex(for id: String) async throws -> String {
    let trimmed = id.trimmed
    guard !trimmed.isEmpty else {
        throw CitationError.unknownIdentifier
    }

    guard let kind = detectIdentifierType(for: trimmed) else {
        throw CitationError.unknownIdentifier
    }

    switch kind {
    case .doi(let doi):
        return try await fetchBibtexFromDOI(doi)
    case .pmidOrPmc(let pmidOrPmc):
        let doi = try await fetchDOIFromPMIDorPMCID(pmidOrPmc)
        return try await fetchBibtexFromDOI(doi)
    case .arxiv(let arxivId):
        let doi = try await fetchDOIFromArxiv(arxivId)
        return try await fetchBibtexFromDOI(doi)
    }
}

// --- DOI → BibTeX ---

private func fetchBibtexFromDOI(_ doi: String) async throws -> String {
    guard
        let encodedDOI = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
        let url = URL(string: "https://doi.org/\(encodedDOI)")
    else {
        throw CitationError.invalidResponse
    }

    var request = URLRequest(url: url)
    request.setValue("application/x-bibtex; charset=utf-8", forHTTPHeaderField: "Accept")

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CitationError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw CitationError.networkError(http.statusCode)
        }
        guard let bibtex = String(data: data, encoding: .utf8) else {
            throw CitationError.invalidResponse
        }
        return bibtex
    } catch let urlError as URLError {
        print("URLError:", urlError, urlError.code)
        throw CitationError.networkError(urlError.errorCode)
    }
}

// --- PMID / PMCID → DOI ---

private struct IdConvResponse: Decodable {
    struct Record: Decodable {
        let doi: String?
    }
    let records: [Record]?
}

private func fetchDOIFromPMIDorPMCID(_ id: String) async throws -> String {
    let trimmed = id.trimmed
    guard
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
        let url = URL(string: "https://www.ncbi.nlm.nih.gov/pmc/utils/idconv/v1.0/?format=json&ids=\(encoded)")
    else {
        throw CitationError.invalidResponse
    }

    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse else {
        throw CitationError.invalidResponse
    }

    guard http.statusCode == 200 else {
        throw CitationError.networkError(http.statusCode)
    }

    let decoded = try JSONDecoder().decode(IdConvResponse.self, from: data)
    guard
        let records = decoded.records,
        let doi = records.first?.doi,
        !doi.isEmpty
    else {
        throw CitationError.missingDOI
    }

    return doi
}

// --- arXiv → DOI ---

private func fetchDOIFromArxiv(_ arxivId: String) async throws -> String {
    let trimmed = arxivId.trimmed
    guard
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
        let url = URL(string: "https://export.arxiv.org/api/query?id_list=\(encoded)")
    else {
        throw CitationError.invalidResponse
    }

    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse else {
        throw CitationError.invalidResponse
    }

    guard http.statusCode == 200 else {
        throw CitationError.networkError(http.statusCode)
    }

    guard let xml = String(data: data, encoding: .utf8) else {
        throw CitationError.invalidResponse
    }

    // Very small, pragmatic XML parsing: look for <arxiv:doi>…</arxiv:doi>
    guard
        let startRange = xml.range(of: "<arxiv:doi>"),
        let endRange = xml.range(of: "</arxiv:doi>", range: startRange.upperBound..<xml.endIndex)
    else {
        throw CitationError.missingDOI
    }

    let doi = String(xml[startRange.upperBound..<endRange.lowerBound]).trimmed
    guard !doi.isEmpty else {
        throw CitationError.missingDOI
    }

    return doi
}

// MARK: - CrossRef search fallback (Algo 3-style)

private struct CrossrefSearchHit: Decodable {
    let doi: String
    let title: String?
    let year: String?

    private enum CodingKeys: String, CodingKey {
        case doi
        case title
        case year
    }
}

private func searchCrossrefForDOI(query: String) async throws -> CrossrefSearchHit {
    guard
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
        let url = URL(string: "https://search.crossref.org/dois?q=\(encoded)&sort=score")
    else {
        throw CitationError.invalidResponse
    }

    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse else {
        throw CitationError.invalidResponse
    }

    guard http.statusCode == 200 else {
        throw CitationError.networkError(http.statusCode)
    }

    let hits = try JSONDecoder().decode([CrossrefSearchHit].self, from: data)
    guard let first = hits.first else {
        throw CitationError.notFound
    }

    return first
}

// MARK: - Final heuristic DOI extraction fallback

/// Extract the first plausible DOI from arbitrary text (e.g. a full reference line),
/// using a simple "find 10.xxxx/..." heuristic.
private func extractDOIFromFreeText(_ text: String) -> String? {
    // Look for something that looks like a DOI.
    // Very rough: start with "10." and continue until a whitespace.
    guard let range = text.range(of: #"10\.\d{4,9}/\S+"#, options: .regularExpression) else {
        return nil
    }

    var candidate = String(text[range])

    // Trim trailing punctuation / brackets often attached to DOIs in text.
    let trailingChars = CharacterSet(charactersIn: ".,;:)]}>\"'")
    candidate = candidate.trimmingCharacters(in: trailingChars)

    return candidate.isEmpty ? nil : candidate
}

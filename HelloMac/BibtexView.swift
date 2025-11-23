//
//  BibtexView.swift
//  HelloMac
//
//  Created by Daniel on 23.11.25.
//


import SwiftUI
import AppKit

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

            Text("Enter DOI, PMCID/PMID, or arXiv ID:")
                .font(.subheadline)

            TextField("e.g. 10.1038/nphys1170, PMC1234567, 2101.00001", text: $identifier)
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
                    .lineLimit(3)
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
            let bibtex = try await fetchBibtex(for: id)
            copyToClipboard(prettyFormatBibtex(bibtex))
            status = "Copied BibTeX to clipboard ✅"
            copied = true
        } catch let error as CitationError {
            status = error.errorDescription
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
    case doi
    case pmidOrPmc
    case arxiv
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
        // e.g. "title={Measured measurement}"
        if field.isEmpty { continue }
        output += "  \(field),\n"
    }

    output += "}"

    return output
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

// MARK: - ID classification (mirrors your Node logic)

private func detectIdentifierType(for id: String) -> IdentifierType? {
    let trimmed = id.trimmed

    // Same patterns used in your Node server:
    // DOI:   ^10\..+/.+$
    // PMID:  ^\d+$|^PMC\d+(\.\d+)?$
    // arXiv: ^\d+\.\d+(v(\d+))?$
    // 

    if trimmed.range(of: #"^10\..+/.+$"#, options: .regularExpression) != nil {
        return .doi
    }

    if trimmed.range(of: #"^\d+$|^PMC\d+(\.\d+)?$"#, options: .regularExpression) != nil {
        return .pmidOrPmc
    }

    if trimmed.range(of: #"^\d+\.\d+(v(\d+))?$"#, options: .regularExpression) != nil {
        return .arxiv
    }

    return nil
}

// MARK: - Networking

private func fetchBibtex(for id: String) async throws -> String {
    guard let kind = detectIdentifierType(for: id) else {
        throw CitationError.unknownIdentifier
    }

    switch kind {
    case .doi:
        return try await fetchBibtexFromDOI(id)
    case .pmidOrPmc:
        let doi = try await fetchDOIFromPMIDorPMCID(id)
        return try await fetchBibtexFromDOI(doi)
    case .arxiv:
        let doi = try await fetchDOIFromArxiv(id)
        return try await fetchBibtexFromDOI(doi)
    }
}

// --- DOI → BibTeX (like doi2bib.doi2bib in your Node code) ---

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

// --- PMID / PMCID → DOI (like pmid2doi in your Node code) ---

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

// --- arXiv → DOI (like arxivid2doi in your Node code) ---

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

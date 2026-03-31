# BibTeX Fetcher

A macOS menu bar app to quickly fetch and copy BibTeX citations from a DOI, PMID, PMCID, arXiv ID, or a full reference string.

## usage

1.  Click the app icon in your menu bar
2.  Paste a DOI, PMID, PMCID, arXiv ID, or a full reference into the text field
3.  Press Enter or click the "Copy BibTeX" button
4.  The BibTeX citation will be automatically copied to your clipboard (if one is found)

## Features

-   Fetches BibTeX from various sources:
    -   [doi.org](https://doi.org)
    -   [NCBI (for PMID/PMCID)](https://www.ncbi.nlm.nih.gov/)
    -   [arXiv](https://arxiv.org/)
-   Fallback search using [CrossRef](https://crossref.org) for plain text queries
-   Heuristically extracts DOIs from full reference strings
-   Formats the BibTeX for easy readability
-   Escapes special characters for LaTeX
-   Sits in your menu bar for easy access

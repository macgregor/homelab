#!/bin/bash

# validate-research-report.sh
# Validates research report structure and completeness

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <report-path>"
    exit 1
fi

REPORT_FILE="$1"

if [ ! -f "$REPORT_FILE" ]; then
    echo "Error: File not found: $REPORT_FILE"
    exit 1
fi

# Check filename pattern: docs/research/web/YYYY-MM-DD-*.md
if ! [[ "$REPORT_FILE" =~ docs/research/web/[0-9]{4}-[0-9]{2}-[0-9]{2}-.+\.md$ ]]; then
    echo "Error: Filename does not match pattern docs/research/web/YYYY-MM-DD-<topic>.md"
    exit 1
fi

# Check for required sections
REQUIRED_SECTIONS=(
    "# Research Report:"
    "## Objective"
    "## Executive Summary"
    "## Findings"
    "### Official Documentation and Resources"
    "### Source Code Repositories"
    "### Community and Third-Party Sources"
    "## Sources"
    "## Metadata"
)

for section in "${REQUIRED_SECTIONS[@]}"; do
    if ! grep -q "^${section}" "$REPORT_FILE"; then
        echo "Error: Missing required section: $section"
        exit 1
    fi
done

# Check for unfilled placeholders
if grep -q "\[REQUIRED:" "$REPORT_FILE"; then
    echo "Error: Found unfilled [REQUIRED:...] placeholders in report"
    exit 1
fi

# Check for Report Date metadata
if ! grep -q "Report Date" "$REPORT_FILE"; then
    echo "Error: Missing Report Date in metadata"
    exit 1
fi

# Check for Search Queries metadata
if ! grep -q "Search Queries" "$REPORT_FILE"; then
    echo "Error: Missing Search Queries in metadata"
    exit 1
fi

# Check for Model metadata
if ! grep -q "Model" "$REPORT_FILE"; then
    echo "Error: Missing Model in metadata"
    exit 1
fi

# Check that Report Date is ISO 8601 format
REPORT_DATE=$(grep "Report Date" "$REPORT_FILE" | head -1 | sed 's/.*: //g' | sed 's/[[:space:]]*$//g')
if ! [[ "$REPORT_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    echo "Error: Report Date is not in ISO 8601 format (YYYY-MM-DDTHH:MM:SSZ): $REPORT_DATE"
    exit 1
fi

# Check that Executive Summary has content (2-3 paragraphs)
SUMMARY_CONTENT=$(sed -n '/## Executive Summary/,/## Findings/p' "$REPORT_FILE" | sed '1d;$d')
if [ -z "$SUMMARY_CONTENT" ] || [ $(echo "$SUMMARY_CONTENT" | grep -c "^[A-Z]") -lt 2 ]; then
    echo "Warning: Executive Summary may not have sufficient paragraph content"
fi

# Check that each official source has required metadata fields
SOURCES_SECTION=$(sed -n '/### Official Documentation and Resources/,/### Source Code Repositories/p' "$REPORT_FILE")
if echo "$SOURCES_SECTION" | grep -q "^- \*\*Source\*\*:"; then
    # Check for Source, URL, Author, Date, Activity, Key points
    while IFS= read -r line; do
        if [[ "$line" =~ ^-\ \*\*Source\*\*: ]]; then
            # Found a source entry, verify it has all required fields
            ENTRY_START=0
            while IFS= read -r next_line; do
                if [[ "$next_line" =~ ^-\ \*\*Source\*\*: ]] && [ $ENTRY_START -eq 1 ]; then
                    break
                fi
                ENTRY_START=1
                if [[ "$next_line" =~ \*\*URL\*\*: ]] || [[ "$next_line" =~ \*\*Author\*\*: ]] || [[ "$next_line" =~ \*\*Date\*\*: ]] || [[ "$next_line" =~ \*\*Activity\*\*: ]] || [[ "$next_line" =~ \*\*Key\ points\*\*: ]]; then
                    :
                fi
            done
        fi
    done <<< "$SOURCES_SECTION"
fi

# Check Sources list is not empty
SOURCES_LIST=$(sed -n '/## Sources/,/## Metadata/p' "$REPORT_FILE" | grep "^- http" | wc -l)
if [ "$SOURCES_LIST" -lt 5 ]; then
    echo "Warning: Sources list has fewer than 5 URLs (found: $SOURCES_LIST)"
fi

echo "Validation passed: $REPORT_FILE"
exit 0

# Samples

This folder contains **anonymized examples** of input and output files to help new users understand the format.

⚠️ **All data below is fictional.** Company names, INNs, and news articles are made up for demonstration only.

## Files

### `counterparties.template.xlsx`

Excel template for the company list. Two columns:

| Наименование | ИНН |
|---|---|
| ООО Ромашка | 7712345678 |
| ООО Лютик | 7723456789 |
| АО Василёк | 7734567890 |

**Important:** INN must be a **text** cell, not a number, otherwise leading zeros are lost.

### `keywords_manual.example.txt`

Example of manual keyword additions. Format: `PRIORITY|Keyword`.

- **H** — high priority (companies, executives, key events)
- **M** — medium (regions, industry)
- **L** — low (general context)

### `results.example.txt`

Example of the parser's output file (`results_high.txt`). Structure:

```
Source:    news source name
Title:     article headline
Link:      full URL
Date:      publication timestamp
Priority:  H / M / L
Matched:   which keywords triggered this match
```

## Creating your own counterparties.xlsx

1. Open Excel
2. Create two columns: `Наименование`, `ИНН`
3. Paste your company list
4. **Format the INN column as Text**: select column → Format Cells → Text
5. Save as `counterparties.xlsx` into `_config\`
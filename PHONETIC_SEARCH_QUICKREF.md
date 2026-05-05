# Phonetic Search - Quick Reference

## Summary
This update adds phonetic search capabilities to handle misspelled names using the **Double Metaphone** algorithm.

---

## Key Changes

### 1. New Index Fields
```json
{
  "name": "FirstName_phonetic",
  "type": "Edm.String",
  "searchable": true,
  "filterable": false,
  "retrievable": false,
  "analyzer": "phonetic_analyzer"
}
```

```json
{
  "name": "LastName_phonetic",
  "type": "Edm.String",
  "searchable": true,
  "filterable": false,
  "retrievable": false,
  "analyzer": "phonetic_analyzer"
}
```

### 2. Custom Analyzer Definition
```json
"analyzers": [
  {
    "name": "phonetic_analyzer",
    "@odata.type": "#Microsoft.Azure.Search.CustomAnalyzer",
    "tokenizer": "standard_v2",
    "tokenFilters": ["lowercase", "phonetic_filter"]
  }
]
```

### 3. Phonetic Token Filter
```json
"tokenFilters": [
  {
    "name": "phonetic_filter",
    "@odata.type": "#Microsoft.Azure.Search.PhoneticTokenFilter",
    "encoder": "doubleMetaphone"
  }
]
```

### 4. Updated Scoring Profile
```json
"text": {
  "weights": {
    "DisplayName": 5,
    "FirstName": 4,
    "LastName": 3,
    "FirstName_phonetic": 2,
    "LastName_phonetic": 2
  }
}
```

---

## Updated Files

| File | Description |
|------|-------------|
| `WorkerIndex-Phonetic.json` | Full index with phonetic support |
| `BasicWorkerIndex-Phonetic.json` | Basic index with phonetic support |
| `SearchQueries-Phonetic.json` | Example queries using phonetic search |
| `Update-AzureAISearch-Phonetic.ps1` | Deployment script |
| `PHONETIC_SEARCH_GUIDE.md` | Complete implementation guide |

---

## Example Queries

### Basic Phonetic Search
```json
{
  "search": "Jon Smyth",
  "searchFields": "FirstName_phonetic, LastName_phonetic, FirstName, LastName",
  "scoringProfile": "boostFirstName"
}
```

### With Filters
```json
{
  "search": "Shawn",
  "searchFields": "FirstName_phonetic, FirstName",
  "filter": "Department eq 'Engineering'",
  "scoringProfile": "boostFirstName"
}
```

### With Semantic Search
```json
{
  "search": "Kathryn Miller",
  "searchFields": "FirstName_phonetic, LastName_phonetic, FirstName, LastName, DisplayName",
  "queryType": "semantic",
  "semanticConfiguration": "people-semantic",
  "scoringProfile": "boostFirstName"
}
```

---

## Common Misspellings Handled

| Misspelling | Matches |
|-------------|---------|
| Jon | John |
| Smythe | Smith, Smyth |
| Cathrine | Catherine, Katherine, Kathryn |
| Steven | Stephen |
| Shawn | Sean, Shaun |
| Kris | Chris |
| Stefanie | Stephanie |
| Jeffery | Jeffrey, Geoffrey |
| Kristina | Christina |

---

## Data Pipeline Updates

When indexing documents, populate phonetic fields with the same data:

```json
{
  "WorkerId": "EMP001",
  "FirstName": "John",
  "FirstName_phonetic": "John",
  "LastName": "Smith",
  "LastName_phonetic": "Smith",
  ...
}
```

The phonetic analyzer applies automatically during indexing. No pre-processing required.

---

## Deployment Options

### Option 1: New Index (Recommended for Testing)
```powershell
.\Update-AzureAISearch-Phonetic.ps1 `
  -ResourceGroupName "rg-aisearch" `
  -SearchServiceName "aisearch-demo" `
  -IndexSchemaPath ".\WorkerIndex-Phonetic.json" `
  -Strategy "NewIndex"
```
Creates: `worker-index-phonetic`

### Option 2: Replace Existing (⚠️ Destructive)
```powershell
.\Update-AzureAISearch-Phonetic.ps1 `
  -ResourceGroupName "rg-aisearch" `
  -SearchServiceName "aisearch-demo" `
  -IndexSchemaPath ".\WorkerIndex-Phonetic.json" `
  -DataFilePath ".\employee-data.json" `
  -Strategy "Replace"
```
Deletes and recreates `worker-index`

### Option 3: Alias (Zero-Downtime)
```powershell
.\Update-AzureAISearch-Phonetic.ps1 `
  -ResourceGroupName "rg-aisearch" `
  -SearchServiceName "aisearch-demo" `
  -IndexSchemaPath ".\WorkerIndex-Phonetic.json" `
  -DataFilePath ".\employee-data.json" `
  -Strategy "Alias"
```
Creates new index + alias for seamless migration

---

## Application Updates

Update your search queries to include phonetic fields:

**Before:**
```csharp
var searchOptions = new SearchOptions
{
    SearchFields = { "FirstName", "LastName", "DisplayName" }
};
```

**After:**
```csharp
var searchOptions = new SearchOptions
{
    SearchFields = { 
        "FirstName", "LastName", "DisplayName",
        "FirstName_phonetic", "LastName_phonetic"
    }
};
```

---

## Testing

1. **Test exact matches** - Ensure existing queries still work
2. **Test phonetic matches** - Try misspelled names:
   - "Jon Smyth" → Should find "John Smith"
   - "Kris" → Should find "Chris"
   - "Stefanie" → Should find "Stephanie"
3. **Test filters** - Verify phonetic search works with filters
4. **Compare relevance** - Check that exact matches rank higher than phonetic

---

## Performance Impact

- **Index Size**: +5-10% (phonetic fields)
- **Query Performance**: Minimal (<10ms typical)
- **Indexing Time**: +2-5% (phonetic analyzer overhead)

---

## Alternative Encoders

To use a different phonetic algorithm, update the token filter:

```json
{
  "name": "phonetic_filter",
  "@odata.type": "#Microsoft.Azure.Search.PhoneticTokenFilter",
  "encoder": "beiderMorse"  // or soundex, metaphone, etc.
}
```

**Available encoders:**
- `doubleMetaphone` ✓ (Recommended for English)
- `beiderMorse` (Multi-language)
- `soundex` (Simple, more false positives)
- `metaphone`
- `caverphone1`, `caverphone2` (NZ accents)
- `koelnerPhonetik` (German names)
- `nysiis`

---

## Troubleshooting

### "Cannot modify analyzer on existing field"
- **Cause**: Analyzers are immutable
- **Solution**: Use NewIndex or Replace strategy

### Phonetic matches return too many results
- **Cause**: Double Metaphone is too aggressive
- **Solution**: Adjust scoring weights or try different encoder

### No phonetic matches found
- **Verify**: Phonetic fields populated during indexing
- **Check**: `searchFields` includes phonetic fields
- **Test**: Use Analyze API to verify phonetic tokens

---

## Resources

- [Complete Guide](./PHONETIC_SEARCH_GUIDE.md)
- [Sample Queries](./SearchQueries-Phonetic.json)
- [Deployment Script](./Update-AzureAISearch-Phonetic.ps1)
- [Azure Docs - Custom Analyzers](https://learn.microsoft.com/azure/search/index-add-custom-analyzers)

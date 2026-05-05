# Phonetic Search Implementation Guide

## Overview
This guide explains how to implement phonetic search in Azure AI Search to handle misspelled names like:
- "John" vs "Jon"
- "Smith" vs "Smyth" or "Smythe"
- "Catherine" vs "Katherine" vs "Kathryn"
- "Sean" vs "Shawn" or "Shaun"
- "Steven" vs "Stephen"

## Changes Made

### 1. Index Schema Updates

#### New Fields Added
Two new phonetic fields have been added to the index:
- `FirstName_phonetic` - Phonetic encoding of first names
- `LastName_phonetic` - Phonetic encoding of last names

These fields:
- Are **searchable** but not retrievable (used only for matching)
- Use the custom `phonetic_analyzer`
- Are not filterable, sortable, or facetable (optimized for search only)

#### Custom Analyzer
A new custom analyzer called `phonetic_analyzer` has been defined:

```json
{
  "name": "phonetic_analyzer",
  "@odata.type": "#Microsoft.Azure.Search.CustomAnalyzer",
  "tokenizer": "standard_v2",
  "tokenFilters": [
    "lowercase",
    "phonetic_filter"
  ]
}
```

#### Phonetic Token Filter
The analyzer uses the **Double Metaphone** algorithm:

```json
{
  "name": "phonetic_filter",
  "@odata.type": "#Microsoft.Azure.Search.PhoneticTokenFilter",
  "encoder": "doubleMetaphone"
}
```

**Double Metaphone** is ideal for:
- English language names
- Handling common spelling variations
- Reducing false positives compared to simpler phonetic algorithms

#### Updated Scoring Profile
The `boostFirstName` scoring profile now includes phonetic fields with moderate weights:

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

This ensures:
- Exact matches are still ranked highest
- Phonetic matches provide fallback results
- Overall search quality improves without disrupting existing behavior

### 2. Data Pipeline Changes

When indexing documents, you need to populate the phonetic fields. Here are the options:

#### Option A: Duplicate Data at Index Time (Recommended)
Simply copy the FirstName and LastName values to the phonetic fields:

```json
{
  "WorkerId": "EMP001",
  "FirstName": "John",
  "FirstName_phonetic": "John",
  "LastName": "Smith",
  "LastName_phonetic": "Smith",
  "DisplayName": "John Smith",
  ...
}
```

Azure AI Search will apply the phonetic analyzer automatically during indexing.

#### Option B: Field Mappings (If using an Indexer)
If you're using an Azure AI Search indexer, add field mappings:

```json
{
  "fieldMappings": [
    {
      "sourceFieldName": "FirstName",
      "targetFieldName": "FirstName_phonetic"
    },
    {
      "sourceFieldName": "LastName",
      "targetFieldName": "LastName_phonetic"
    }
  ]
}
```

#### Option C: Skillset with Custom Code
For more complex scenarios, use a custom skill to generate phonetic encodings:

```json
{
  "@odata.type": "#Microsoft.Skills.Custom.WebApiSkill",
  "name": "phonetic-encoder",
  "uri": "https://your-function.azurewebsites.net/api/encode-phonetic",
  "context": "/document",
  "inputs": [
    { "name": "firstName", "source": "/document/FirstName" },
    { "name": "lastName", "source": "/document/LastName" }
  ],
  "outputs": [
    { "name": "firstNamePhonetic", "targetName": "FirstName_phonetic" },
    { "name": "lastNamePhonetic", "targetName": "LastName_phonetic" }
  ]
}
```

### 3. Query Pattern Updates

#### Basic Phonetic Search
Use `searchFields` to include phonetic fields:

```json
{
  "search": "Jon Smyth",
  "searchFields": "FirstName_phonetic, LastName_phonetic, FirstName, LastName",
  "scoringProfile": "boostFirstName"
}
```

#### Phonetic Search with Semantic Ranking
Combine phonetic matching with semantic search:

```json
{
  "search": "Kathryn Miller",
  "searchFields": "FirstName_phonetic, LastName_phonetic, FirstName, LastName, DisplayName",
  "queryType": "semantic",
  "semanticConfiguration": "people-semantic",
  "scoringProfile": "boostFirstName"
}
```

#### Phonetic Search with Filters
Narrow results by department or location:

```json
{
  "search": "Shawn",
  "searchFields": "FirstName_phonetic, FirstName",
  "filter": "Department eq 'Engineering'",
  "scoringProfile": "boostFirstName"
}
```

## Deployment Steps

### Step 1: Update the Index
Use the updated index definition files:
- `WorkerIndex-Phonetic.json`
- `BasicWorkerIndex-Phonetic.json`

⚠️ **Important**: You cannot update an existing index with new analyzers. You must:
1. Create a new index with the phonetic configuration, OR
2. Delete and recreate the existing index

### Step 2: Re-index Your Data
After updating the index schema:
1. Update your data pipeline to populate phonetic fields
2. Re-index all existing documents
3. For Option A (recommended): Simply include the FirstName/LastName values in the phonetic fields

### Step 3: Update Your Application
Update search queries to include phonetic fields in `searchFields` parameter.

### Step 4: Test Phonetic Matches
Use the example queries in `SearchQueries-Phonetic.json` to verify:
- "Kris" matches "Chris"
- "Smythe" matches "Smith"
- "Steven Jonson" matches "Stephen Johnson"

## Performance Considerations

1. **Index Size**: Phonetic fields add minimal overhead (~5-10% increase)
2. **Query Performance**: Phonetic searches are slightly slower than exact matches
3. **Relevance**: Use scoring profiles to balance exact vs phonetic matches
4. **False Positives**: Double Metaphone is generally accurate but may occasionally match unrelated names

## Alternative Phonetic Encoders

Azure AI Search supports other phonetic encoders if Double Metaphone doesn't meet your needs:

- **`soundex`**: Simpler algorithm, more false positives
- **`metaphone`**: Predecessor to Double Metaphone
- **`caverphone1`** / **`caverphone2`**: Optimized for New Zealand accents
- **`beiderMorse`**: Better for multiple languages, more complex
- **`koelnerPhonetik`**: Optimized for German names
- **`nysiis`**: Focuses on similarity rather than pronunciation

To change the encoder, update the token filter:

```json
{
  "name": "phonetic_filter",
  "@odata.type": "#Microsoft.Azure.Search.PhoneticTokenFilter",
  "encoder": "beiderMorse"
}
```

## Testing Recommendations

1. **Create test cases** with common misspellings in your domain
2. **Monitor search analytics** to identify frequent typos
3. **A/B test** phonetic vs non-phonetic searches
4. **Adjust scoring weights** based on user feedback
5. **Consider hybrid approach**: Use phonetic search as fallback when exact search returns few results

## Example Results

With phonetic search enabled, users searching for:
- "Jon Smith" will find "John Smith"
- "Cathrine" will find "Catherine", "Katherine", "Kathryn"
- "Stefanie" will find "Stephanie"
- "Shaun" will find "Sean", "Shawn"
- "Steven" will find "Stephen"

## Additional Resources

- [Azure AI Search Custom Analyzers](https://learn.microsoft.com/azure/search/index-add-custom-analyzers)
- [Phonetic Token Filter Reference](https://learn.microsoft.com/azure/search/index-add-custom-analyzers#phonetic-token-filter)
- [Scoring Profiles](https://learn.microsoft.com/azure/search/index-add-scoring-profiles)

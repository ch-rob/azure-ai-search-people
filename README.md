# Azure AI Search - Employee Directory

This project contains a PowerShell script to create and configure an Azure AI Search resource for searching employee data that mimics Microsoft Entra ID Graph data.

## Files

- **Create-AzureAISearch.ps1** - PowerShell script to create Azure AI Search service and configure the employee index
- **WorkerIndex.json** - Index schema definition with advanced features (scoring profiles, semantic search, vector search)
- **employee-data.json** - Sample employee data in JSON format (75 employees with challenging name patterns)
- **README.md** - This file

## Prerequisites

- Azure subscription
- PowerShell 5.1 or PowerShell 7+
- Azure PowerShell modules (Az.Accounts, Az.Resources, Az.Search)
- Appropriate permissions to create Azure resources

## Setup

### Install Azure PowerShell Modules

If you haven't already, install the Azure PowerShell modules:

```powershell
Install-Module -Name Az -Force -AllowClobber -Scope CurrentUser
```

**Important:** After installing the Az modules for the first time, **close and reopen your PowerShell session** before running the deployment script. This prevents assembly loading conflicts.

## Employee Data Schema

The WorkerIndex.json defines a comprehensive employee search index with the following core fields:

### Core Identity Fields
- **WorkerId** - Unique employee identifier (key field)
- **DisplayName**, **FirstName**, **LastName** - Name fields
- **WorkEmail**, **UserPrincipalName**, **AccountName** - Email identifiers

### Organizational Fields
- **Title**, **Department**, **Function**, **Level** - Job information
- **Manager**, **DirectReports**, **ExtendedManagers** - Reporting structure
- **Company**, **WorkerType** - Employment details

### Location Fields
- **Location**, **Office**, **Country** - Geographic information
- **BuildingNr**, **Floor**, **Room** - Physical location details
- **LocationCode**, **LocationDescription**, **MnetSearchLocation** - Location metadata

### Financial & Operations
- **CostCenterCode**, **CostCenterDescription** - Cost tracking
- **LegalEntityCode**, **LegalEntityDescription** - Legal structure
- **ProductCode**, **ProductDescription** - Product association

### Additional Information
- **Skills**, **PastProjects**, **Interests** - Profile enrichment
- **MnetPronouns**, **Time_zone** - Personal preferences
- **MnetLastHireDate**, **MnetWorkPhone** - HR data
- **Picture**, **MnetSpaceID** - Media and workspace
- **Content**, **SearchableContent** - Full-text searchable content

### Advanced Search Features
- **contentVector**, **SearchableContentVector** - Vector embeddings for semantic/AI search (1536 dimensions)
- **MnetNameVariants** - Alternative name spellings and variations

## Index Capabilities

The WorkerIndex.json includes advanced Azure AI Search features:

- ✅ **Scoring Profile** (`boostFirstName`) - Prioritizes DisplayName, FirstName, and LastName in search results
- ✅ **Semantic Search** (`people-semantic`) - AI-powered relevance ranking
- ✅ **Vector Search** - HNSW algorithm for embedding-based similarity search
- ✅ **BM25 Similarity** - Industry-standard ranking algorithm
- ✅ **Full-text search** with standard Lucene analyzer
- ✅ **Faceting** on most fields for filtering
- ✅ **Sorting** on key fields

## Usage

### Basic Deployment (without data)

```powershell
.\Create-AzureAISearch.ps1 `
    -ResourceGroupName "rg-aisearch-demo" `
    -SearchServiceName "aisearch-employees-001" `
    -Location "eastus"
```

### Deployment with Sample Data

```powershell
.\Create-AzureAISearch.ps1 `
    -ResourceGroupName "rg-aisearch-demo" `
    -SearchServiceName "aisearch-employees-001" `
    -Location "westus2" `
    -SkuName "standard" `
    -IndexSchemaPath ".\WorkerIndex.json" `
    -DataFilePath ".\employee-data.json"
```

### Advanced Options (use standard which can use vector search, semantic search, and more)

```powershell
.\Create-AzureAISearch.ps1 `
    -ResourceGroupName "rg-aisearch-demo" `
    -SearchServiceName "aisearch-employees-001" `
    -Location "westus2" `
    -SkuName "standard" `
    -IndexSchemaPath ".\WorkerIndex.json" `
    -DataFilePath ".\employee-data.json"
```

## Parameters

- **ResourceGroupName** (Required) - Azure Resource Group name
- **SearchServiceName** (Required) - Unique name for the AI Search service
- **Location** (Required) - Azure region (e.g., eastus, westus2, centralus)
- **SkuName** (Optional) - Pricing tier: free, basic, standard, etc. Default: basic
- **IndexSchemaPath** (Optional) - Path to index schema JSON file. Default: .\WorkerIndex.json
- **DataFilePath** (Optional) - Path to JSON file with employee data

## Search Examples

Once deployed, you can search using the Azure Portal or REST API:

### Simple Search
```
Sarah
```

### Field-Specific Search
```
Title:Engineer
```

### Complex Query
```
Title:Engineer AND Department:Engineering
```

### Filter Examples
```
$filter=Department eq 'Engineering'
$filter=OfficeLocation eq 'Seattle'
```

## Sample Data

The included `employee-data.json` contains **75 sample employees** across various departments with challenging name patterns for testing search capabilities:
- Engineering
- Product
- Design
- Data & Analytics
- Human Resources
- Marketing
- Sales
- Finance
- Customer Success
- Security
- Quality Assurance
- IT Operations

### Name Testing Patterns
The dataset includes employees with:
- **Short/long name variations** (Jim vs. James, Mike vs. Michael, etc.)
- **Similar prefixes** (Chris, Christina, Christine, Christopher)
- **Last names matching first names** (Alex Benjamin, Chris Michael, etc.)
- **Multiple employees with same surnames** (Anderson, Miller, Harris, Jackson, etc.)
- **Nickname variations** (Nick/Nicholas, Liz/Elizabeth/Beth, etc.)

These patterns help test Azure AI Search's:
- Fuzzy matching capabilities
- Exact vs. partial search
- Name disambiguation
- Relevance scoring

## Features

- ✅ Full-text search across employee names and titles
- ✅ Filtering by department, location, and other fields
- ✅ Sortable results
- ✅ Faceting for departments and locations
- ✅ Auto-suggest/autocomplete for search queries
- ✅ CORS enabled for web applications

## Cleanup

To delete the resources:

```powershell
Remove-AzSearchService -ResourceGroupName "rg-aisearch-demo" -Name "aisearch-employees-001"
Remove-AzResourceGroup -Name "rg-aisearch-demo" -Force
```

## Next Steps

1. **Test searches** in the Azure Portal Search Explorer
2. **Integrate with applications** using Azure SDK or REST API
3. **Configure authentication** using Azure AD or API keys
4. **Set up data sources** for automated indexing from your actual Entra ID
5. **Add semantic search** capabilities for improved relevance
6. **Implement skillsets** for AI enrichment

## Additional Resources

- [Azure AI Search Documentation](https://learn.microsoft.com/azure/search/)
- [Azure AI Search REST API](https://learn.microsoft.com/rest/api/searchservice/)
- [Microsoft Graph API](https://learn.microsoft.com/graph/overview)

<#
.SYNOPSIS
    Updates an Azure AI Search index to add phonetic search capabilities for handling misspelled names.

.DESCRIPTION
    This script demonstrates how to update an existing Azure AI Search index with phonetic analyzers,
    or create a new index with phonetic support. Since analyzers cannot be modified on an existing index,
    you'll need to either:
    1. Create a new index with a different name
    2. Delete and recreate the existing index
    3. Use alias swapping for zero-downtime migration

.PARAMETER ResourceGroupName
    The name of the Azure Resource Group containing the Search service.

.PARAMETER SearchServiceName
    The name of the Azure AI Search service.

.PARAMETER IndexSchemaPath
    Path to the phonetic-enabled index JSON file. 
    Options: '.\WorkerIndex-Phonetic.json' or '.\BasicWorkerIndex-Phonetic.json'

.PARAMETER DataFilePath
    Path to employee data JSON file to re-index.

.PARAMETER Strategy
    Deployment strategy:
    - 'NewIndex': Creates a new index with '-phonetic' suffix
    - 'Replace': Deletes and recreates the existing index (DESTRUCTIVE!)
    - 'Alias': Creates new index and uses alias for zero-downtime (requires standard tier or above)

.EXAMPLE
    # Create a new index with phonetic support
    .\Update-AzureAISearch-Phonetic.ps1 -ResourceGroupName "rg-aisearch" -SearchServiceName "aisearch-demo" `
        -IndexSchemaPath ".\WorkerIndex-Phonetic.json" -Strategy "NewIndex"

.EXAMPLE
    # Replace existing index (WARNING: deletes current index first!)
    .\Update-AzureAISearch-Phonetic.ps1 -ResourceGroupName "rg-aisearch" -SearchServiceName "aisearch-demo" `
        -IndexSchemaPath ".\WorkerIndex-Phonetic.json" -DataFilePath ".\employee-data.json" -Strategy "Replace"

.EXAMPLE
    # Use alias strategy for zero-downtime migration
    .\Update-AzureAISearch-Phonetic.ps1 -ResourceGroupName "rg-aisearch" -SearchServiceName "aisearch-demo" `
        -IndexSchemaPath ".\WorkerIndex-Phonetic.json" -DataFilePath ".\employee-data.json" -Strategy "Alias"

.NOTES
    IMPORTANT: You cannot modify analyzers on an existing index. You must:
    - Create a new index, OR
    - Delete and recreate the index

    When re-indexing, ensure the phonetic fields contain the same data as the source fields:
    - FirstName_phonetic should contain FirstName value
    - LastName_phonetic should contain LastName value
    The phonetic analyzer will be applied automatically during indexing.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$SearchServiceName,

    [Parameter(Mandatory = $false)]
    [string]$IndexSchemaPath = '.\WorkerIndex-Phonetic.json',

    [Parameter(Mandatory = $false)]
    [string]$DataFilePath,

    [Parameter(Mandatory = $false)]
    [ValidateSet('NewIndex', 'Replace', 'Alias')]
    [string]$Strategy = 'NewIndex'
)

$ErrorActionPreference = 'Stop'

#region Helper Functions

function Write-Status {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ✓ $Message" -ForegroundColor Green
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ✗ $Message" -ForegroundColor Red
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ⚠ $Message" -ForegroundColor Yellow
}

function Prepare-IndexSchema {
    param([PSCustomObject]$SchemaObject)
    
    # Remove OData and read-only properties
    $propertiesToRemove = @('@odata.etag', '@odata.context', 'purviewEnabled')
    foreach ($prop in $propertiesToRemove) {
        if ($SchemaObject.PSObject.Properties[$prop]) {
            $SchemaObject.PSObject.Properties.Remove($prop)
        }
    }
    
    # Remove empty arrays
    $emptyArrayProps = @('suggesters', 'normalizers', 'tokenizers', 'charFilters')
    foreach ($prop in $emptyArrayProps) {
        if ($SchemaObject.PSObject.Properties[$prop]) {
            if ($SchemaObject.$prop -is [Array] -and $SchemaObject.$prop.Count -eq 0) {
                $SchemaObject.PSObject.Properties.Remove($prop)
            }
        }
    }
    
    # Clean semantic configuration
    if ($SchemaObject.semantic -and $SchemaObject.semantic.configurations) {
        foreach ($config in $SchemaObject.semantic.configurations) {
            $semanticPropsToRemove = @('flightingOptIn', 'rankingOrder')
            foreach ($prop in $semanticPropsToRemove) {
                if ($config.PSObject.Properties[$prop]) {
                    $config.PSObject.Properties.Remove($prop)
                }
            }
        }
    }
    
    # Clean vector search configuration
    if ($SchemaObject.vectorSearch) {
        $vectorPropsToRemove = @('vectorizers', 'compressions')
        foreach ($prop in $vectorPropsToRemove) {
            if ($SchemaObject.vectorSearch.PSObject.Properties[$prop]) {
                if ($SchemaObject.vectorSearch.$prop -is [Array] -and $SchemaObject.vectorSearch.$prop.Count -eq 0) {
                    $SchemaObject.vectorSearch.PSObject.Properties.Remove($prop)
                }
            }
        }
    }
    
    # Clean field properties
    if ($SchemaObject.fields) {
        foreach ($field in $SchemaObject.fields) {
            if ($field.PSObject.Properties['stored']) {
                $field.PSObject.Properties.Remove('stored')
            }
            if ($field.synonymMaps -and $field.synonymMaps.Count -eq 0) {
                $field.PSObject.Properties.Remove('synonymMaps')
            }
        }
    }
    
    return $SchemaObject
}

function Add-PhoneticDataToDocument {
    param([PSCustomObject]$Document)
    
    # Copy FirstName to FirstName_phonetic
    if ($Document.FirstName) {
        $Document | Add-Member -MemberType NoteProperty -Name "FirstName_phonetic" -Value $Document.FirstName -Force
    }
    
    # Copy LastName to LastName_phonetic
    if ($Document.LastName) {
        $Document | Add-Member -MemberType NoteProperty -Name "LastName_phonetic" -Value $Document.LastName -Force
    }
    
    return $Document
}

#endregion

try {
    Write-Status "Starting phonetic search update..."

    # Authenticate
    Write-Status "Checking Azure authentication..."
    $azContext = Get-AzContext
    if (-not $azContext) {
        Write-Status "Logging in to Azure..."
        Connect-AzAccount
        $azContext = Get-AzContext
    }
    Write-Success "Authenticated as: $($azContext.Account.Id)"

    # Get admin key
    Write-Status "Retrieving admin key..."
    $adminKey = (Get-AzSearchAdminKeyPair -ResourceGroupName $ResourceGroupName -ServiceName $SearchServiceName).Primary
    Write-Success "Admin key retrieved"

    # Load index schema
    Write-Status "Loading phonetic index schema from $IndexSchemaPath..."
    if (-not (Test-Path $IndexSchemaPath)) {
        Write-ErrorMessage "Index schema file not found: $IndexSchemaPath"
        exit 1
    }
    
    $indexSchemaJson = Get-Content -Path $IndexSchemaPath -Raw
    $indexSchemaObject = $indexSchemaJson | ConvertFrom-Json
    
    # Clean schema for API
    $indexSchemaObject = Prepare-IndexSchema -SchemaObject $indexSchemaObject
    
    $originalIndexName = $indexSchemaObject.name
    $apiVersion = "2023-11-01"
    $searchEndpoint = "https://$SearchServiceName.search.windows.net"
    $headers = @{
        'Content-Type' = 'application/json'
        'api-key'      = $adminKey
    }

    # Determine target index name based on strategy
    $targetIndexName = $originalIndexName
    
    switch ($Strategy) {
        'NewIndex' {
            $targetIndexName = "$originalIndexName-phonetic"
            Write-Status "Strategy: Creating new index with name '$targetIndexName'"
            $indexSchemaObject.name = $targetIndexName
        }
        
        'Replace' {
            Write-Warning-Custom "Strategy: Replace will DELETE the existing index '$originalIndexName'"
            $confirmation = Read-Host "Are you sure you want to DELETE and recreate the index? Type 'YES' to confirm"
            if ($confirmation -ne 'YES') {
                Write-ErrorMessage "Operation cancelled by user"
                exit 1
            }
            
            # Delete existing index
            Write-Status "Deleting existing index '$originalIndexName'..."
            try {
                $deleteUrl = "$searchEndpoint/indexes/$originalIndexName`?api-version=$apiVersion"
                Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers -ErrorAction Stop
                Write-Success "Index deleted"
                Start-Sleep -Seconds 5
            } catch {
                if ($_.Exception.Response.StatusCode -eq 404) {
                    Write-Status "Index doesn't exist (404), continuing..."
                } else {
                    throw
                }
            }
        }
        
        'Alias' {
            $targetIndexName = "$originalIndexName-phonetic-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Write-Status "Strategy: Alias - Creating new index '$targetIndexName' with alias '$originalIndexName'"
            $indexSchemaObject.name = $targetIndexName
        }
    }

    # Create/update the index
    Write-Status "Creating index '$targetIndexName'..."
    $indexSchema = $indexSchemaObject | ConvertTo-Json -Depth 20
    $indexUrl = "$searchEndpoint/indexes/$targetIndexName`?api-version=$apiVersion"
    
    try {
        $response = Invoke-RestMethod -Uri $indexUrl -Method Put -Headers $headers -Body $indexSchema -ErrorAction Stop
        Write-Success "Index '$targetIndexName' created successfully"
    } catch {
        Write-ErrorMessage "Failed to create index: $($_.Exception.Message)"
        if ($_.ErrorDetails) {
            Write-Host $_.ErrorDetails.Message -ForegroundColor Red
        }
        exit 1
    }

    # Upload data if provided
    if ($DataFilePath) {
        Write-Status "Loading data from $DataFilePath..."
        if (-not (Test-Path $DataFilePath)) {
            Write-ErrorMessage "Data file not found: $DataFilePath"
            exit 1
        }
        
        $dataJson = Get-Content -Path $DataFilePath -Raw
        $dataArray = $dataJson | ConvertFrom-Json
        
        if ($dataArray -isnot [Array]) {
            $dataArray = @($dataArray)
        }
        
        Write-Status "Processing $($dataArray.Count) documents (adding phonetic fields)..."
        
        # Add phonetic fields to each document
        $documentsWithPhonetic = @()
        foreach ($doc in $dataArray) {
            $docWithPhonetic = Add-PhoneticDataToDocument -Document $doc
            $documentsWithPhonetic += $docWithPhonetic
        }
        
        # Upload in batches
        $batchSize = 1000
        $batches = [Math]::Ceiling($documentsWithPhonetic.Count / $batchSize)
        
        for ($i = 0; $i -lt $batches; $i++) {
            $start = $i * $batchSize
            $end = [Math]::Min($start + $batchSize, $documentsWithPhonetic.Count)
            $batch = $documentsWithPhonetic[$start..($end - 1)]
            
            $uploadBody = @{
                value = $batch | ForEach-Object {
                    $_ | Add-Member -MemberType NoteProperty -Name '@search.action' -Value 'upload' -Force -PassThru
                }
            } | ConvertTo-Json -Depth 20
            
            $uploadUrl = "$searchEndpoint/indexes/$targetIndexName/docs/index?api-version=$apiVersion"
            
            try {
                Write-Status "Uploading batch $($i + 1) of $batches (documents $start to $($end - 1))..."
                $uploadResponse = Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $headers -Body $uploadBody -ErrorAction Stop
                Write-Success "Batch $($i + 1) uploaded successfully"
                Start-Sleep -Seconds 2
            } catch {
                Write-ErrorMessage "Failed to upload batch $($i + 1): $($_.Exception.Message)"
            }
        }
        
        Write-Success "All documents uploaded"
    }

    # Handle alias strategy
    if ($Strategy -eq 'Alias') {
        Write-Status "Creating/updating alias '$originalIndexName' to point to '$targetIndexName'..."
        
        $aliasBody = @{
            indexes = @($targetIndexName)
        } | ConvertTo-Json
        
        $aliasUrl = "$searchEndpoint/aliases/$originalIndexName`?api-version=$apiVersion"
        
        try {
            Invoke-RestMethod -Uri $aliasUrl -Method Put -Headers $headers -Body $aliasBody -ErrorAction Stop
            Write-Success "Alias '$originalIndexName' now points to '$targetIndexName'"
            Write-Success "Applications using '$originalIndexName' will automatically use the new phonetic index"
        } catch {
            Write-ErrorMessage "Failed to create/update alias: $($_.Exception.Message)"
            Write-Host "You can manually create an alias using the Azure Portal" -ForegroundColor Yellow
        }
    }

    Write-Success "`nPhonetic search update completed!"
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "1. Test phonetic queries using SearchQueries-Phonetic.json" -ForegroundColor White
    Write-Host "2. Update your application to include phonetic fields in 'searchFields' parameter" -ForegroundColor White
    Write-Host "3. Monitor search analytics to verify improved results for misspelled names" -ForegroundColor White
    
    if ($Strategy -eq 'NewIndex') {
        Write-Host "`nNote: Your application needs to be updated to use index name: $targetIndexName" -ForegroundColor Yellow
    }
    
} catch {
    Write-ErrorMessage "Script failed: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}

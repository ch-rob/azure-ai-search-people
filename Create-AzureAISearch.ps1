<#
.SYNOPSIS
    Creates an Azure AI Search resource and configures it with an employee data index.

.DESCRIPTION
    This script creates an Azure AI Search service, defines an index schema for Entra Graph-like
    employee data, and optionally uploads sample data from a JSON file.

.PARAMETER ResourceGroupName
    The name of the Azure Resource Group where the Search service will be created.

.PARAMETER SearchServiceName
    The name of the Azure AI Search service (must be globally unique).

.PARAMETER Location
    The Azure region where the Search service will be created (e.g., 'eastus', 'westus2').

.PARAMETER SkuName
    The pricing tier for the Search service. Options: 'free', 'basic', 'standard', 'standard2', 'standard3', 'storage_optimized_l1', 'storage_optimized_l2'.
    Default: 'basic'

.PARAMETER IndexSchemaPath
    Path to the JSON file containing the index schema definition. Default: '.\WorkerIndex.json'

.PARAMETER DataFilePath
    Optional path to a JSON file containing employee data to upload.

.EXAMPLE
    .\Create-AzureAISearch.ps1 -ResourceGroupName "rg-aisearch-demo" -SearchServiceName "aisearch-employees-001" -Location "eastus"

.EXAMPLE
    .\Create-AzureAISearch.ps1 -ResourceGroupName "rg-aisearch-demo" -SearchServiceName "aisearch-employees-001" -Location "eastus" -DataFilePath ".\employee-data.json"

.EXAMPLE
    .\Create-AzureAISearch.ps1 -ResourceGroupName "rg-aisearch-demo" -SearchServiceName "aisearch-employees-001" -Location "eastus" -IndexSchemaPath ".\WorkerIndex.json" -DataFilePath ".\employee-data.json"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$SearchServiceName,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $false)]
    [ValidateSet('free', 'basic', 'standard', 'standard2', 'standard3', 'storage_optimized_l1', 'storage_optimized_l2')]
    [string]$SkuName = 'basic',

    [Parameter(Mandatory = $false)]
    [string]$IndexSchemaPath = '.\WorkerIndex.json',

    [Parameter(Mandatory = $false)]
    [string]$DataFilePath
)

# Set error action preference
$ErrorActionPreference = 'Stop'

#region Functions

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

#endregion

try {
    Write-Status "Starting Azure AI Search deployment..."

    # Check if Azure PowerShell module is installed
    Write-Status "Checking for Azure PowerShell modules..."
    $requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Search')
    $missingModules = @()
    
    foreach ($moduleName in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $moduleName)) {
            $missingModules += $moduleName
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-ErrorMessage "Missing modules: $($missingModules -join ', ')"
        Write-Host "`nPlease install the required modules by running:" -ForegroundColor Yellow
        Write-Host "  Install-Module -Name Az -Force -AllowClobber -Scope CurrentUser" -ForegroundColor White
        Write-Host "`nThen restart your PowerShell session and run this script again.`n" -ForegroundColor Yellow
        exit 1
    }

    # Import required modules (only if not already imported)
    Write-Status "Loading Azure PowerShell modules..."
    foreach ($moduleName in $requiredModules) {
        if (-not (Get-Module -Name $moduleName)) {
            try {
                Import-Module $moduleName -ErrorAction Stop
                Write-Success "$moduleName loaded"
            } catch {
                Write-ErrorMessage "Failed to load $moduleName. Please restart your PowerShell session."
                Write-Host "If you just installed the Az modules, you must close and reopen PowerShell.`n" -ForegroundColor Yellow
                exit 1
            }
        } else {
            Write-Success "$moduleName already loaded"
        }
    }

    # Check if logged in to Azure
    Write-Status "Checking Azure authentication..."
    $azContext = Get-AzContext
    if (-not $azContext) {
        Write-Status "Not logged in. Initiating Azure login..."
        Connect-AzAccount
        $azContext = Get-AzContext
    }
    Write-Success "Authenticated as: $($azContext.Account.Id)"

    # Create or verify Resource Group
    Write-Status "Checking Resource Group: $ResourceGroupName..."
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $rg) {
        Write-Status "Creating Resource Group: $ResourceGroupName in $Location..."
        $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
        Write-Success "Resource Group created"
    } else {
        Write-Success "Resource Group exists"
    }

    # Create Azure AI Search Service
    Write-Status "Creating Azure AI Search service: $SearchServiceName..."
    $searchService = Get-AzSearchService -ResourceGroupName $ResourceGroupName -Name $SearchServiceName -ErrorAction SilentlyContinue
    
    $isNewService = $false
    if (-not $searchService) {
        $searchService = New-AzSearchService `
            -ResourceGroupName $ResourceGroupName `
            -Name $SearchServiceName `
            -Location $Location `
            -Sku $SkuName `
            -PartitionCount 1 `
            -ReplicaCount 1
        
        $isNewService = $true
        Write-Success "Azure AI Search service created successfully"
    } else {
        Write-Success "Azure AI Search service already exists"
    }

    # Wait for service to be fully provisioned (if newly created)
    if ($isNewService) {
        Write-Status "Waiting for search service to be fully provisioned..."
        $maxRetries = 10
        $retryCount = 0
        $provisioned = $false
        
        while ($retryCount -lt $maxRetries -and -not $provisioned) {
            Start-Sleep -Seconds 5
            $retryCount++
            
            try {
                $searchService = Get-AzSearchService -ResourceGroupName $ResourceGroupName -Name $SearchServiceName -ErrorAction Stop
                if ($searchService.ProvisioningState -eq 'Succeeded') {
                    $provisioned = $true
                    Write-Success "Search service is ready (took $($retryCount * 5) seconds)"
                } else {
                    Write-Host "  Status: $($searchService.ProvisioningState) - waiting... ($($retryCount * 5)s)" -ForegroundColor Gray
                }
            } catch {
                Write-Host "  Checking provisioning status... ($($retryCount * 5)s)" -ForegroundColor Gray
            }
        }
        
        if (-not $provisioned) {
            Write-ErrorMessage "Service provisioning timed out. It may still be provisioning - check Azure Portal."
            Write-Host "You can run this script again once the service is ready.`n" -ForegroundColor Yellow
            exit 1
        }
        
        # Additional wait for DNS propagation
        Write-Status "Waiting for DNS propagation..."
        Start-Sleep -Seconds 10
    }

    # Get admin key for REST API calls
    Write-Status "Retrieving admin key..."
    $adminKey = (Get-AzSearchAdminKeyPair -ResourceGroupName $ResourceGroupName -ServiceName $SearchServiceName).Primary
    Write-Success "Admin key retrieved"

    # Construct API endpoint
    $apiVersion = "2023-11-01"
    $searchEndpoint = "https://$SearchServiceName.search.windows.net"
    
    # Load index schema from JSON file
    Write-Status "Loading index schema from $IndexSchemaPath..."
    if (-not (Test-Path $IndexSchemaPath)) {
        Write-ErrorMessage "Index schema file not found: $IndexSchemaPath"
        exit 1
    }
    
    $indexSchemaJson = Get-Content -Path $IndexSchemaPath -Raw
    $indexSchemaObject = $indexSchemaJson | ConvertFrom-Json
    
    # Remove OData and read-only properties that cause 400 errors
    $propertiesToRemove = @('@odata.etag', '@odata.context', 'purviewEnabled')
    foreach ($prop in $propertiesToRemove) {
        if ($indexSchemaObject.PSObject.Properties[$prop]) {
            $indexSchemaObject.PSObject.Properties.Remove($prop)
        }
    }
    
    # Remove empty analyzer/normalizer arrays (not supported in create/update API)
    $emptyArrayProps = @('analyzers', 'normalizers', 'tokenizers', 'tokenFilters', 'charFilters')
    foreach ($prop in $emptyArrayProps) {
        if ($indexSchemaObject.PSObject.Properties[$prop]) {
            if ($indexSchemaObject.$prop -is [Array] -and $indexSchemaObject.$prop.Count -eq 0) {
                $indexSchemaObject.PSObject.Properties.Remove($prop)
            }
        }
    }
    
    # Clean up semantic configuration (remove unsupported properties)
    if ($indexSchemaObject.semantic -and $indexSchemaObject.semantic.configurations) {
        foreach ($config in $indexSchemaObject.semantic.configurations) {
            # Remove properties not supported in API version
            $semanticPropsToRemove = @('flightingOptIn', 'rankingOrder')
            foreach ($prop in $semanticPropsToRemove) {
                if ($config.PSObject.Properties[$prop]) {
                    $config.PSObject.Properties.Remove($prop)
                }
            }
        }
    }
    
    # Clean up vector search configuration (remove unsupported properties/empty arrays)
    if ($indexSchemaObject.vectorSearch) {
        $vectorPropsToRemove = @('vectorizers', 'compressions')
        foreach ($prop in $vectorPropsToRemove) {
            if ($indexSchemaObject.vectorSearch.PSObject.Properties[$prop]) {
                # Remove if it's an empty array or exists
                if ($indexSchemaObject.vectorSearch.$prop -is [Array] -and $indexSchemaObject.vectorSearch.$prop.Count -eq 0) {
                    $indexSchemaObject.vectorSearch.PSObject.Properties.Remove($prop)
                } elseif ($null -eq $indexSchemaObject.vectorSearch.$prop) {
                    $indexSchemaObject.vectorSearch.PSObject.Properties.Remove($prop)
                }
            }
        }
    }
    
    # Clean up field properties (remove 'stored' and empty 'synonymMaps')
    if ($indexSchemaObject.fields) {
        foreach ($field in $indexSchemaObject.fields) {
            # Remove 'stored' property (implicit in the API)
            if ($field.PSObject.Properties['stored']) {
                $field.PSObject.Properties.Remove('stored')
            }
            # Remove empty synonymMaps arrays
            if ($field.synonymMaps -and $field.synonymMaps.Count -eq 0) {
                $field.PSObject.Properties.Remove('synonymMaps')
            }
        }
    }
    
    # Get the index name from the schema
    $IndexName = $indexSchemaObject.name
    Write-Success "Index schema loaded: $IndexName (cleaned for API compatibility)"
    
    # Convert back to JSON for API call
    $indexSchema = $indexSchemaObject | ConvertTo-Json -Depth 20

    # Create index using REST API
    $headers = @{
        'Content-Type'  = 'application/json'
        'api-key'       = $adminKey
    }

    $indexUrl = "$searchEndpoint/indexes/$($IndexName)?api-version=$apiVersion"
    
    # Retry logic for index creation (handles transient SSL/network issues)
    $maxRetries = 5
    $retryDelay = 10
    $indexCreated = $false
    
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            Write-Status "Creating/updating index (attempt $i of $maxRetries)..."
            $response = Invoke-RestMethod -Uri $indexUrl -Method Put -Headers $headers -Body $indexSchema -ErrorAction Stop
            Write-Success "Index '$IndexName' created/updated successfully"
            $indexCreated = $true
            break
        } catch {
            if ($_.Exception.Response.StatusCode -eq 'NoContent' -or $_.Exception.Response.StatusCode -eq 'OK') {
                Write-Success "Index '$IndexName' created/updated successfully"
                $indexCreated = $true
                break
            }
            
            # For 400 errors, show detailed message and don't retry
            if ($_.Exception.Response.StatusCode -eq 400) {
                Write-ErrorMessage "Bad Request (400) - Invalid index schema"
                
                # Try to get detailed error message
                $errorDetails = ""
                try {
                    if ($_.ErrorDetails.Message) {
                        $errorDetails = $_.ErrorDetails.Message
                        $errorObj = $errorDetails | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($errorObj.error) {
                            Write-Host "`nError from Azure:" -ForegroundColor Yellow
                            Write-Host "  Code: $($errorObj.error.code)" -ForegroundColor Red
                            Write-Host "  Message: $($errorObj.error.message)" -ForegroundColor Red
                        } else {
                            Write-Host "`nError details:" -ForegroundColor Yellow
                            Write-Host $errorDetails -ForegroundColor Red
                        }
                    }
                } catch {
                    Write-Host "`nError message: $($_.Exception.Message)" -ForegroundColor Red
                }
                
                Write-Host "`nYour search service tier: $SkuName" -ForegroundColor Yellow
                Write-Host "`nLikely cause:" -ForegroundColor Yellow
                Write-Host "  The WorkerIndex.json includes advanced features (vector search, semantic search)" -ForegroundColor Gray
                Write-Host "  that require Standard tier or higher, but you're using '$SkuName' tier.`n" -ForegroundColor Gray
                
                Write-Host "Solutions:" -ForegroundColor Cyan
                Write-Host "  Option 1: Upgrade to Standard tier - Re-run with:" -ForegroundColor White
                Write-Host "    -SkuName 'standard'" -ForegroundColor Green
                Write-Host "`n  Option 2: Use a simplified index - Create a basic schema without vectors/semantic." -ForegroundColor White
                Write-Host "`n"
                throw
            }
            
            # For other errors, retry
            if ($i -lt $maxRetries) {
                Write-Host "  Attempt $i failed: $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Host "  Retrying in $retryDelay seconds..." -ForegroundColor Gray
                Start-Sleep -Seconds $retryDelay
            } else {
                Write-ErrorMessage "Failed to create index after $maxRetries attempts"
                Write-Host "`nError details: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "`nPossible solutions:" -ForegroundColor Yellow
                Write-Host "  1. Check your internet connection" -ForegroundColor Gray
                Write-Host "  2. Verify the search service is accessible in Azure Portal" -ForegroundColor Gray
                Write-Host "  3. Check for any proxy/firewall restrictions" -ForegroundColor Gray
                Write-Host "  4. Wait a few minutes and try running the script again`n" -ForegroundColor Gray
                throw
            }
        }
    }

    # Upload data if file path is provided
    if ($DataFilePath -and (Test-Path $DataFilePath)) {
        Write-Status "Loading data from $DataFilePath..."
        $jsonData = Get-Content -Path $DataFilePath -Raw | ConvertFrom-Json
        
        # Prepare upload payload
        $uploadPayload = @{
            value = @($jsonData | ForEach-Object {
                $_ | Add-Member -NotePropertyName '@search.action' -NotePropertyValue 'upload' -Force -PassThru
            })
        } | ConvertTo-Json -Depth 10

        $uploadUrl = "$searchEndpoint/indexes/$IndexName/docs/index?api-version=$apiVersion"
        
        # Retry logic for data upload
        $uploadSuccess = $false
        for ($i = 1; $i -le $maxRetries; $i++) {
            try {
                Write-Status "Uploading employee data to index (attempt $i of $maxRetries)..."
                $uploadResponse = Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $headers -Body $uploadPayload -ErrorAction Stop
                Write-Success "Successfully uploaded $($uploadResponse.value.Count) documents"
                $uploadSuccess = $true
                break
            } catch {
                if ($i -lt $maxRetries) {
                    Write-Host "  Upload attempt $i failed, retrying in $retryDelay seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds $retryDelay
                } else {
                    Write-ErrorMessage "Failed to upload data after $maxRetries attempts"
                    Write-Host "Index was created but data upload failed: $($_.Exception.Message)" -ForegroundColor Yellow
                    Write-Host "You can manually upload the data later or re-run the script.`n" -ForegroundColor Gray
                }
            }
        }
    }

    # Display summary
    Write-Host "`n" -NoNewline
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "  Azure AI Search Deployment Summary" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "  Service Name     : " -NoNewline -ForegroundColor Gray
    Write-Host $SearchServiceName -ForegroundColor White
    Write-Host "  Resource Group   : " -NoNewline -ForegroundColor Gray
    Write-Host $ResourceGroupName -ForegroundColor White
    Write-Host "  Location         : " -NoNewline -ForegroundColor Gray
    Write-Host $Location -ForegroundColor White
    Write-Host "  SKU              : " -NoNewline -ForegroundColor Gray
    Write-Host $SkuName -ForegroundColor White
    Write-Host "  Index Name       : " -NoNewline -ForegroundColor Gray
    Write-Host $IndexName -ForegroundColor White
    Write-Host "  Search Endpoint  : " -NoNewline -ForegroundColor Gray
    Write-Host $searchEndpoint -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "`nNext Steps:" -ForegroundColor Cyan
    Write-Host "  • Test search queries in Azure Portal" -ForegroundColor Gray
    Write-Host "  • Configure authentication (API keys or Azure AD)" -ForegroundColor Gray
    Write-Host "  • Set up indexers for automated data ingestion" -ForegroundColor Gray
    Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor Yellow

} catch {
    Write-ErrorMessage "An error occurred: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}

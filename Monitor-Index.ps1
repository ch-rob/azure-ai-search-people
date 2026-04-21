<#
.SYNOPSIS
    Monitor Azure AI Search index status and test phonetic search

.PARAMETER ResourceGroupName
    Resource group name

.PARAMETER SearchServiceName
    Search service name

.PARAMETER IndexName
    Index name (default: worker-index-phonetic)

.EXAMPLE
    .\Monitor-Index.ps1 -ResourceGroupName rg-aisearch-demo -SearchServiceName aisearch-employees-001
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$SearchServiceName,

    [Parameter(Mandatory = $false)]
    [string]$IndexName = "worker-index-phonetic"
)

$ErrorActionPreference = 'Stop'

# Get admin key
$adminKey = (Get-AzSearchAdminKeyPair -ResourceGroupName $ResourceGroupName -ServiceName $SearchServiceName).Primary
$headers = @{
    'api-key'      = $adminKey
    'Content-Type' = 'application/json'
}
$baseUrl = "https://$SearchServiceName.search.windows.net"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Azure AI Search Index Monitor" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Service: $SearchServiceName" -ForegroundColor White
Write-Host "Index: $IndexName" -ForegroundColor White
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White

# Get index statistics
Write-Host "`n--- Index Statistics ---" -ForegroundColor Yellow
try {
    $stats = Invoke-RestMethod -Uri "$baseUrl/indexes/$IndexName/stats?api-version=2023-11-01" -Headers $headers
    Write-Host "Document Count: " -NoNewline -ForegroundColor Gray
    Write-Host $stats.documentCount -ForegroundColor Green
    
    $storageMB = [math]::Round($stats.storageSize / 1MB, 2)
    Write-Host "Storage Size: " -NoNewline -ForegroundColor Gray
    if ($stats.storageSize -eq 0) {
        Write-Host "$($stats.storageSize) bytes (metrics updating...)" -ForegroundColor Yellow
    } else {
        Write-Host "$storageMB MB ($($stats.storageSize) bytes)" -ForegroundColor Green
    }
    
    if ($stats.vectorIndexSize -gt 0) {
        $vectorMB = [math]::Round($stats.vectorIndexSize / 1MB, 2)
        Write-Host "Vector Index Size: " -NoNewline -ForegroundColor Gray
        Write-Host "$vectorMB MB" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to get statistics: $($_.Exception.Message)" -ForegroundColor Red
}

# Test basic search
Write-Host "`n--- Search Test ---" -ForegroundColor Yellow
try {
    $searchBody = @{
        search = '*'
        count  = $true
        top    = 3
        select = 'WorkerId,DisplayName,FirstName,LastName'
    } | ConvertTo-Json
    
    $searchResponse = Invoke-RestMethod -Uri "$baseUrl/indexes/$IndexName/docs/search?api-version=2023-11-01" `
        -Method Post -Headers $headers -Body $searchBody
    
    Write-Host "Search Status: " -NoNewline -ForegroundColor Gray
    Write-Host "✓ Working" -ForegroundColor Green
    Write-Host "Searchable Documents: " -NoNewline -ForegroundColor Gray
    Write-Host $searchResponse.'@odata.count' -ForegroundColor Green
    
    Write-Host "`nSample Results:" -ForegroundColor Gray
    $searchResponse.value | ForEach-Object {
        Write-Host "  • $($_.DisplayName) ($($_.WorkerId))" -ForegroundColor White
    }
} catch {
    Write-Host "Search Status: " -NoNewline -ForegroundColor Gray
    Write-Host "✗ Failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test phonetic search
Write-Host "`n--- Phonetic Search Tests ---" -ForegroundColor Yellow

$phoneticTests = @(
    @{ Query = "Kris"; Field = "FirstName_phonetic"; Expected = "Chris" },
    @{ Query = "Jon"; Field = "FirstName_phonetic"; Expected = "John" },
    @{ Query = "Smyth"; Field = "LastName_phonetic"; Expected = "Smith" },
    @{ Query = "Steven"; Field = "FirstName_phonetic"; Expected = "Stephen" }
)

foreach ($test in $phoneticTests) {
    Write-Host "`nSearching for '$($test.Query)' (expecting '$($test.Expected)'):" -ForegroundColor Gray
    
    try {
        $searchBody = @{
            search       = $test.Query
            searchFields = "$($test.Field),FirstName,LastName"
            select       = 'DisplayName,FirstName,LastName'
            top          = 3
        } | ConvertTo-Json
        
        $result = Invoke-RestMethod -Uri "$baseUrl/indexes/$IndexName/docs/search?api-version=2023-11-01" `
            -Method Post -Headers $headers -Body $searchBody
        
        if ($result.value.Count -gt 0) {
            $result.value | ForEach-Object {
                Write-Host "  ✓ Found: $($_.DisplayName)" -ForegroundColor Green
            }
        } else {
            Write-Host "  ⚠ No matches found" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ✗ Search failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Check for common issues
Write-Host "`n--- Health Check ---" -ForegroundColor Yellow

$issues = @()

if ($stats.storageSize -eq 0 -and $stats.documentCount -gt 0) {
    Write-Host "⚠ Storage metrics not yet updated (this is normal initially)" -ForegroundColor Yellow
} elseif ($stats.documentCount -eq 0) {
    $issues += "No documents in index"
}

if ($searchResponse.'@odata.count' -ne $stats.documentCount) {
    $issues += "Mismatch between document count and searchable documents"
}

if ($issues.Count -eq 0) {
    Write-Host "✓ All checks passed!" -ForegroundColor Green
} else {
    Write-Host "Issues detected:" -ForegroundColor Red
    $issues | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
}

Write-Host "`n========================================`n" -ForegroundColor Cyan

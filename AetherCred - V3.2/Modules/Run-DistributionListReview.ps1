function Invoke-DistributionListReview {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    Write-Host "Initiating Distribution List Review..." -ForegroundColor Cyan

    try {
        Write-Host "Fetching all groups to identify distribution lists..."
        $allGroups = Get-MgGroup -All -Property "displayName,mail,createdDateTime,mailEnabled,securityEnabled"
        $distroLists = $allGroups | Where-Object { $_.MailEnabled -eq $true -and $_.SecurityEnabled -eq $false }
        
        Write-Host "Found $($distroLists.Count) distribution lists."

        if ($distroLists.Count -eq 0) {
            Write-Host "No distribution lists found."
            return $null
        }

        $data = @()
        Write-Host "Processing distribution list data..."
        foreach ($dl in $distroLists) {
            
            $emailAddress = if (-not [string]::IsNullOrWhiteSpace($dl.mail)) { $dl.mail } else { "N/A" }

            $data += [PSCustomObject]@{
                DisplayName           = $dl.displayName
                Email                 = $emailAddress
                CreatedDate           = Get-Date $dl.createdDateTime
            }
        }
        
        Write-Host "Distribution List Review completed successfully." -ForegroundColor Green
        return $data
    }
    catch {
        Write-Error "Failed to execute Distribution List Review. Error: $($_.Exception.Message)"
        return $null
    }
}

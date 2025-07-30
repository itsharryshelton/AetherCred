<#
.SYNOPSIS
    AetherCred module to retrieve and analyze Shared Mailbox accounts.

.DESCRIPTION
    This script contains the function to perform the Shared Mailbox review.
    It is designed to be called by the AetherCred-Core.ps1 script.
    It retrieves all shared mailboxes, identified as users without a usageLocation,
    and reports on their core details.

.NOTES
    For this module to function correctly, the Entra App Registration requires the following
    Microsoft Graph API permissions (Application type):
    - User.Read.All
#>

# ==============================================================================
# EXPORTED FUNCTION: Invoke-SharedMailboxReview
# ==============================================================================
function Invoke-SharedMailboxReview {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    Write-Host "Initiating Shared Mailbox Review..." -ForegroundColor Cyan

    try {
        # Fetch all user accounts that are members, then filter locally for those without a usageLocation.
        Write-Host "Fetching all member accounts to identify shared mailboxes..."
        $allMembers = Get-MgUser -All -Filter "userType eq 'Member'" -Property "Id,displayName,mail,userPrincipalName,createdDateTime,usageLocation"
        $sharedMailboxes = $allMembers | Where-Object { -not $_.usageLocation }
        
        Write-Host "Found $($sharedMailboxes.Count) potential shared mailboxes."

        if ($sharedMailboxes.Count -eq 0) {
            Write-Host "No shared mailboxes found."
            return $null # Return null to trigger the "No data" handling in the core script
        }

        $data = @()
        Write-Host "Processing shared mailbox data..."
        foreach ($mailbox in $sharedMailboxes) {
            
            # CORRECTED: Use an 'if' statement to reliably select the email or UPN, avoiding the -or operator's boolean behavior.
            $emailAddress = if (-not [string]::IsNullOrWhiteSpace($mailbox.mail)) { $mailbox.mail } else { $mailbox.userPrincipalName }

            $data += [PSCustomObject]@{
                DisplayName        = $mailbox.displayName
                Email              = $emailAddress
                CreatedDate        = Get-Date $mailbox.createdDateTime
            }
        }
        
        Write-Host "Shared Mailbox Review completed successfully." -ForegroundColor Green
        return $data
    }
    catch {
        Write-Error "Failed to execute Shared Mailbox Review. Error: $($_.Exception.Message)"
        return $null
    }
}

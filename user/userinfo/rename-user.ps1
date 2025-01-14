<#
  .SYNOPSIS
  Rename a user or mailbox. Will not update metadata like DisplayName, GivenName, Surname.

  .DESCRIPTION
  Rename a user or mailbox. Will not update metadata like DisplayName, GivenName, Surname.

  .NOTES
  Permissions: 
  MS Graph API
  - Directory.Read.All
  - User.ReadWrite.All
  AzureAD Roles:
  - Exchange administrator
  Office 365 Exchange Online API
  - Exchange.ManageAsApp

  .INPUTS
  RunbookCustomization: {
        "Parameters": {
            "CallerName": {
                "Hide": true
            }
        }
    }

#>

#Requires -Modules @{ModuleName = "RealmJoin.RunbookHelper"; ModuleVersion = "0.6.0" }, ExchangeOnlineManagement

param(
    [Parameter(Mandatory = $true)] 
    [ValidateScript( { Use-RJInterface -Type Graph -Entity User -DisplayName "User/Mailbox" } )]
    [string] $UserName,
    [Parameter(Mandatory = $true)]
    [ValidateScript( { Use-RJInterface -DisplayName "New UserPrincipalName" } )]
    [string] $NewUpn,
    [ValidateScript( { Use-RJInterface -DisplayName "Change MailNickname based on new UPN" } )]
    [bool] $ChangeMailnickname = $true,
    [ValidateScript( { Use-RJInterface -DisplayName "Update primary eMail address" } )]
    [bool] $UpdatePrimaryAddress = $true,
    # CallerName is tracked purely for auditing purposes
    [Parameter(Mandatory = $true)]
    [string] $CallerName
    ## Currently, removing the old eMail-address "in one go" seems not to work reliably
    # [bool] $RemoveOldAddress = $false
)

"## Trying to rename a user/mailbox '$UserName'. Will not update metadata like DisplayName, GivenName, Surname."

try {
    Connect-RjRbGraph
    Connect-RjRbExchangeOnline

    ## Get original UPN
    # $userObject = Invoke-RjRbRestMethodGraph -resource "/users/$UserName" 

    # Change UPN
    $body = @{
        userPrincipalName = $NewUpn
    }
    Invoke-RjRbRestMethodGraph -resource "/users/$UserName" -Method Patch -Body $body | Out-Null

    # Change eMail-Adresses
    $mailbox = Get-EXOMailbox -Identity $UserName -ErrorAction SilentlyContinue
    if ($mailbox) {

        if ($ChangeMailnickname) {
            Set-Mailbox -Identity $UserName -Name $NewUpn.split('@')[0] -alias $NewUpn.split('@')[0] | Out-Null
        }

        if ($UpdatePrimaryAddress) {

            $newAdresses = New-Object System.Collections.ArrayList
            $newAdresses.Add("SMTP:$NewUpn") | Out-Null

            foreach ($address in $mailbox.EmailAddresses) {
                $prefix = $address.Split(":")[0] 
                $mail = $address.Split(":")[1]
            
                if ($prefix -eq "smtp") {
                    if ($mail -ne $NewUpn ) {
                        $newAdresses.Add($address.ToLower()) | Out-Null
                    }
                    # not smtp: not including the SIP address will automatically update it to the new default address.
                    # Updating SIP takes some minutes to propagate after rename
                }
            }
            Set-Mailbox -Identity $UserName -EmailAddresses $newAdresses | Out-Null
        }
    }
    
    "## User '$UserName' successfully renamed to '$NewUpn'"
}
finally {
    Disconnect-ExchangeOnline -ErrorAction SilentlyContinue -Confirm:$true | Out-Null
}


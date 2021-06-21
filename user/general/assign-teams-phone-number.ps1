# This runbook will assign a phone number to a teams-enabled user to enable calling
#
# Permissions: 
# The MicrosoftTeams PS module requires to use a "real user account" for some operations.
# This user will need the Azure AD role "Teams Administrator"

# Be aware: MicrosoftTeams Module only wotk with PS 5.x, not 7
#Requires -Modules @{ModuleName = "RealmJoin.RunbookHelper"; ModuleVersion = "0.5.1" }, MicrosoftTeams 

param(
    [Parameter(Mandatory = $true)]
    [String] $UserName,
    [Parameter(Mandatory = $false)]
    [string] $Number,
    [bool] $allow_International_Calls = $true,
    [Parameter(Mandatory = $true)]
    [string] $OrganizationId 
)

try {
    $Global:VerbosePreference = "SilentlyContinue"

    #$AutomationConnectionName = "AzureRunAsConnection"
    #$autoCon = Get-AutomationConnection -Name $AutomationConnectionName
    #Connect-MicrosoftTeams -TenantId "primepulse.de" -ApplicationId $autoCon.ApplicationId -CertificateThumbprint $autoCon.CertificateThumbprint | Out-Null

    $cred = Get-AutomationPSCredential -name "teamsautomation"
    Connect-MicrosoftTeams -TenantId $OrganizationId -Credential $cred | Out-Null

    ## Woraround - "+" gets lost...
    if (($Number.Length -gt 0) -and -not $Number.StartsWith("0")) {
        $Number = "+" + $Number
    }
    ## Check if Number is E.164
    if ($Number -notmatch "^\+\d{8,13}") {
        throw "Number needs to be in E.164 format ( '+#######...' )."
    }

    # "Number: '$Number'"

    ## change number to lineURI
    $LineURI = "tel:" + $Number

    $someUser = Get-CsOnlineUser -TenantId $autoCon.TenantId -Filter "LineURI -eq '$LineURI'" -ErrorAction SilentlyContinue
    if ($someUser) {
        "$Number is already assigned to to $($someUser.UserPrincipalName)"
    }

    # "Number not assigned"

    $CsOnlineUser = Get-CsOnlineUser -Identity $UserName -ErrorAction SilentlyContinue
    if (-not $CsOnlineUser) {
        "$UserName seems not to be Teams enabled."
    }
    
    # "User Checks complete"
    # TODO: Check for licensing like "MCOEV"

    $CsOnlineTelephoneNumber = Get-CsOnlineTelephoneNumber -TelephoneNumber ($Number).replace("+", "") -WarningAction ignore
    if ($CsOnlineTelephoneNumber) {
        #### Calling Plan Part ####

        # Search Emergency Location
        $CsOnlineLisLocation = Get-CsOnlineLisLocation | where-object { $_.City -eq $CsOnlineUser.City -and $_.PostalCode -eq $CsOnlineUser.PostalCode -and ($_.StreetName + " " + $_.HouseNumber + $_.HouseNumberSuffix) -eq $CsOnlineUser.StreetAddress }
        if ($CsOnlineLisLocation) {
            Set-CsOnlineVoiceUser -Identity $UserName -TelephoneNumber $Number -LocationID $CsOnlineLisLocation.LocationId[0]
        }
        else {
            Set-CsOnlineVoiceUser -Identity $UserName -TelephoneNumber $Number
            Write-RjRbLog -Message "WARNING: No Emergency-Location could be found for this User. Maybe the Users Attributes (Postal Code, City and Street Adress) are not filled correctly."
        }

        #### Calling Plan Part End ####
    }
    else {
        #### Direct Routing Part ####

        ## Asign Number
        try {
            Set-CsUser `
                -Identity $UserName `
                -EnterpriseVoiceEnabled $true `
                -HostedVoiceMail $true `
                -OnPremLineURI $LineURI `
                -ErrorAction Stop
        }
        catch { throw "Error assigning the Number. Please make sure, a MS Phone System license is assigned to the user." }

        ### If our default OnlineVoiceRoutingPolicy exists
        if ((Get-CsOnlineVoiceRoutingPolicy).Identity -eq "WorldWide") {
            ## Assign appropriate OnlineVoiceRoutingPolicy
            try {
                If ($Number -like "+49*") { Grant-CsOnlineVoiceRoutingPolicy -PolicyName WorldWide -Identity $UserName }
                If ($Number -like "+1*") { Grant-CsOnlineVoiceRoutingPolicy -PolicyName WorldWide -Identity $UserName }
                If ($Number -like "+971*") { Grant-CsOnlineVoiceRoutingPolicy -PolicyName WorldWide -Identity $UserName }
                If ($Number -like "+52*") { Grant-CsOnlineVoiceRoutingPolicy -PolicyName WorldWide -Identity $UserName }
            }
            catch { Write-Error "Error assigning OnlineVoiceRoutingPolicy" -Exception $_.Exception -ErrorAction Continue; exit }
        }
        #### Direct Routing Part End ###
    }

    # "Phoneno set"

    ## Set CsUserPstnSettings to allow International Calls if requested
    if ($allow_International_Calls) {
        try {
            Set-CsUserPstnSettings -Identity $UserName -AllowInternationalCalls $true
        }
        catch { Write-Error "Error assigning PstnSettings" -Exception $_.Exception -ErrorAction Continue; exit }
    }
}
finally {
    Disconnect-MicrosoftTeams -Confirm:$false | Out-Null
}
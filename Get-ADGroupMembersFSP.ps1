<#
<#PSScriptInfo
 
.VERSION
1.0.0

.GUID
c05766cc-8031-45fe-a45f-cd1420c642ce

.AUTHOR
Jan Tiedemann

.COMPANYNAME
Microsoft

.COPYRIGHT November 2021

.TAGS
ADGroup Groupmembers ActiveDirectory Groups Members FSP

.DESCRIPTION
Get the group membership an its Foreign Security Pricipals and translate them to a NTAccount.

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
#>

<#
 
.DESCRIPTION
Gets the group membership and its Foreign Security Pricipals and translate them to a NTAccount.
.INPUTS
An ActiveDirectory group name as string
.OUTPUTS
Returns a object with NoteProperties DistinguisehdName, ObjectClass, NTAccount
.PARAMETER GroupName
    Required. This parameter represents the name of the group to investigate.
.PARAMETER Recursive
    Optional. This parameter tells the function to do a recursive membership query.
.EXAMPLE
     Get-ADGroupMembersFSP.ps1 -GroupName "Domain Admins"
     This example will output an object with all direct memebers of the Domain Admins group with their DN, ObjectClass and NTAccount
.EXAMPLE
    Get-ADGroupMembersFSP.ps1 -GroupName "Domain Admins" -Recursive
    This example will output an object with all recursive memebers of the Domain Admins group with their DN, ObjectClass and NTAccount
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true,
        Position = 0,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "Enter GroupName to get members")]
    [ValidateNotNullOrEmpty()]
    [String]$GroupName,
    
    [Parameter(Mandatory = $false,
        Position = 1,
        ValueFromPipelineByPropertyName = $false,
        HelpMessage = "Enter DomainFQDN from initial Group")]
    [ValidateNotNullOrEmpty()]
    [String]$DomainName = [System.Net.Dns]::GetHostEntry($env:computername).HostName.Split(".", 2)[1],    
    
    [Parameter(Mandatory = $false,
        Position = 2)]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty, 
    
    [Parameter(Mandatory = $false,
        Position = 3,
        HelpMessage = "Enter GroupName to get members from")]
    [Switch]$Recursive = $false
)

#region HelperFuntions
function Get-Trusts {
    [CmdletBinding()]  
    param (
        $Domain,
        [pscredential]$Credential
    )
    $trustInfo = @()
    $trustlist = Get-ADObject -LDAPFilter '(objectClass=trustedDomain)' `
        -Server $Domain `
        -Properties securityIdentifier, Name, TrustDirection
    foreach ($trust in $trustlist) {
        if ($trust.TrustDirection -eq 2 -or $trust.TrustDirection -eq 3) {
            $htTrust = @{ }
            $htTrust.Name = $trust.Name
            $htTrust.SID = $trust.securityIdentifier.ToString()
            $objTrust = New-Object psobject -Property $htTrust
            $trustInfo += $objTrust
        }
    }
    return $trustInfo
}
function Get-DomainFromDN {
    [CmdletBinding()]
    param (
        $DN
    )
    $domain = $DN -Split "," | Where-Object { $_ -like "DC=*" }
    $domain = $domain -join "." -replace ("DC=", "")
    return $domain
}  
function Get-AllMembersFromGroup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true,
            Position = 0,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Enter GroupName to get members")]
        [ValidateNotNullOrEmpty()]
        [String]$GroupName,
        
        [Parameter(Mandatory = $false,
            Position = 1,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Enter Active Directory Domain FQDN")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainName = [System.Net.Dns]::GetHostEntry($env:computername).HostName.Split(".", 2)[1]
    )
    begin {
        $MemberList = @()
        $ObjectInfo = @()
    }
    process {
        try {
            # Array of group members
            $MemberList = ((Get-ADGroup -Identity $GroupName -Server $DomainName -Properties Members).Members) 
            foreach ($memberDN in $MemberList) {
                # From UserDN make Domain FQDN
                $domain = Get-DomainFromDN -DN $memberDN
                # Check if DN Object is a group or other type
                $AdObject = (Get-ADObject $memberDN -Server $domain -Properties DistinguishedName, ObjectClass, Name)
                $ObjectList = [PSCustomObject][ordered]@{
                    DistinguishedName = $memberDN
                    ObjectClass       = $AdObject.ObjectClass
                }
                If ($AdObject.objectClass -eq "group") {
                    do {
                        # Adds PsCustomObject to Array
                        $ObjectInfo += $ObjectList
                        Write-Debug "Group: $AdObject.DistinguishedName"
                        Get-AllMembersFromGroup -GroupName $AdObject.DistinguishedName -DomainName $domain
                    } while (-Not($ObjectList.DistinguishedName.Contains($AdObject.DistinguishedName)))                
                }
                Elseif ($AdObject.objectClass -eq "user") {
                    do {
                        # Adds PsCustomObject to Arra
                        $ObjectInfo += $ObjectList
                        Write-Debug "User: $AdObject.DistinguishedName"
                    } while (-Not($ObjectList.DistinguishedName.Contains($AdObject.DistinguishedName)))
                }
                Else {
                    do {
                        # Adds PsCustomObject to Arra
                        $ObjectInfo += $ObjectList
                        Write-Debug "Others: $AdObject.DistinguishedName"
                    } while (-Not($ObjectList.DistinguishedName.Contains($AdObject.DistinguishedName)))                    
                }
                
            }
        }
        catch {
            Write-Host "$Error[0].Exception.InnerException.Message"
        }
    }
    end {
        Return ([object[]]$ObjectInfo)
    }
}
function Get-MyMembers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true,
            Position = 0,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Enter GroupName to get members")]
        [ValidateNotNullOrEmpty()]
        [string]$GroupName,
        
        [Parameter(Mandatory = $true,
        Position = 1,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "Enter DomainFQDN to get group members from")]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName,

        [Parameter(Mandatory = $false)]
        [PsCredential]$Credential,
        
        [Parameter(Mandatory = $false)]
        [switch]$Recursive = $false
    )
    switch ($Recursive) {
        $false { 
            $ObjectInfo = @()
            try {
                if ($Credential) {
                    $myMemberList = (Get-ADGroup $GroupName -Credential $Credential -Properties Members).Members
                }
                elseif ($Credential -and $DomainName) {
                    $myMemberList = (Get-ADGroup $GroupName -Credential $Credential -Server $DomainName -Properties Members).Members
                }
                else {
                    $myMemberList = (Get-ADGroup $GroupName -Server $DomainName -Properties Members).Members
                }
                foreach ($memberDN in $myMemberList) {
                    # From UserDN make Domain FQDN
                    $domain = Get-DomainFromDN -DN $memberDN
                    # Check if DN Object is a group or other type
                    if ($Credential.IsPresent) {
                        $AdObject = (Get-ADObject $memberDN -Server $domain -Credential $Credential -Properties DistinguishedName, ObjectClass, Name)
                    }
                    else {
                        $AdObject = (Get-ADObject $memberDN -Server $domain -Properties DistinguishedName, ObjectClass, Name)
                    }
                    $ObjectList = [PSCustomObject][ordered]@{
                        DistinguishedName = $memberDN
                        ObjectClass       = $AdObject.ObjectClass
                    }
                    $ObjectInfo += $ObjectList
                }
                return $ObjectInfo
            }
            catch {
                Write-Host "$Error[0].Exception.InnerException.Message"
            }
        }
        $true {
            $ObjectInfo = @()
            try {
                $ObjectInfo = Get-AllMembersFromGroup -GroupName $GroupName -DomainName $DomainName
            }
            catch {
                Write-Host "$Error[0].Exception.InnerException.Message"
            }
            return $ObjectInfo 
        }
    }
    
}
function Resolve-FSPs {
    [CmdletBinding()]
    param (
        $GroupMembers
    )
    $newList = @()
    foreach ($member in $GroupMembers) {
        if ($member -like "*ForeignSecurityPrincipals*" ) {
            # Extract SID from foreign security principal DN
            if ($member -like "*ACNF:*") {
                # CNF stands for conflict, you should check your AD.
                $FSPSID = $member.substring($member.indexof("=") + 1, $($member.indexof("\") - 3))
            }
            else {
                $FSPSID = $member.substring($member.indexof("=") + 1, $($member.indexof(",") - 3))
            }
            try {
                # Translate FSBSid to NTAccount (aka Domain\user)
                $SID = New-Object System.Security.Principal.SecurityIdentifier($FSPSID)
                $Resolved = $SID.Translate([System.Security.Principal.NTAccount])
                $newList += $Resolved.Value
                Write-Debug "Resolved FSP-SID: $Resolved.Value"
            }
            catch {
                # If SID can't be translated add at least FSB DN to new array
                $newList += $member
                Write-Debug "Unresolved FSP-SID: $member"
            }
        }
        else {
            # From UserDN make Domain FQDN
            $domain = Get-DomainFromDN -DN $member
            # Get domain\user (aka msDS-PrincipalName) from ADUser DN
            $principalName = (Get-ADObject $member -Server $domain -Properties msDS-PrincipalName)."msDS-PrincipalName" 
            $newList += $principalName
            Write-Debug "Normal Account: $principalName"
        }
    }
    return $newList
}
#endregion

#region main
try {
    Import-Module ActiveDirectory
}
Catch {
    Write-Host "ActiveDirectory Module couldn't be loaded"
    break
}
$memberDNs = @()
$membersNTAccounts = @()
Clear-Host
switch ($Recursive) {
    $false {
        if ($Credential.IsPresent) {
            $memberDNs = Get-MyMembers -GroupName $GroupName -Credential $Credential -DomainName $DomainName
            $membersNTAccounts = Resolve-FSPs -GroupMembers ($memberDNs).DistinguishedName           
        }
        else {
            $memberDNs = Get-MyMembers -GroupName $GroupName -DomainName $DomainName
            $membersNTAccounts = Resolve-FSPs -GroupMembers ($memberDNs).DistinguishedName
        }
        # Merge the two Objects to one
        If (($memberDNs).count -gt 1) {
            for ($i = 0; $i -lt $membersNTAccounts.Count; $i++) {
                $memberDNs.Item($i) | Add-Member -MemberType NoteProperty -Name 'NTAccount' -Value ($($membersNTAccounts.Item($i)))
            }
        }
        # Merge the two Objects to one, when only one member exists in group
        else {
            $memberDNs | Add-Member -MemberType NoteProperty -Name 'NTAccount' -Value ($($membersNTAccounts))
        }   

    }
    $true {
        $memberDNs = Get-MyMembers -GroupName $GroupName -DomainName $DomainName -Recursive
        $membersNTAccounts = Resolve-FSPs -GroupMembers ($memberDNs).DistinguishedName
        # Merge the two Objects to one
        If (($memberDNs).count -gt 1) {
            for ($i = 0; $i -lt $membersNTAccounts.Count; $i++) {
                $memberDNs.Item($i) | Add-Member -MemberType NoteProperty -Name 'NTAccount' -Value ($($membersNTAccounts.Item($i)))
            }
        }
        # Merge the two Objects to one, when only one member exists in group
        else {
            $memberDNs | Add-Member -MemberType NoteProperty -Name 'NTAccount' -Value ($($membersNTAccounts))
        }   
    }
}
$memberDNs
#endregion
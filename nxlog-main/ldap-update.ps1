# Purpose:      This script exports all groups and their recursive membership from Active Directory into XML-API format for PAN-OS
# Author:        Shane Smith

# Loads user and group data into Hashtables
Function Get-ADData {
    $script:users = @{}
    $script:groups = @{}
    $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
    $script:domains = $domain.Forest.Domains

    $domains | ForEach-Object {
        $domain = $_.Name
        # Load user data
        Get-ADUser -Server $domain -Filter * -Properties UserPrincipalName,PrimaryGroup | select distinguishedName,UserPrincipalName,PrimaryGroup | ForEach {
            $employee = $_
            $distinguishedName = $employee.distinguishedName
            $users.Add($distinguishedName,$employee)
        }
        #Load group data
        Get-ADGroup -Server $domain -Filter * -Properties members | select distinguishedName,name,members | ForEach {
            $group = $_
            $distinguishedName = $group.distinguishedName
            $groups.Add($distinguishedName,$group)
        }
    }
}

Function Get-Members
{
    $groupDN = $args[0]
    # If the current group hasn't been traversed already, proceed
    If (-not $currentGroupList.Contains($groupDN)) { 
        # If the current group hasn't been populated with members, populate the group with members
        If (-not $explodedGroups.ContainsKey($groupDN)) {
            $members = @()
            $explodedGroups.Add($groupDN,$members)
            $group = $groups.$groupDN
            $group.Members | ForEach-Object {
                $memberDN = $_
                # If the member is a user, add it as a member
                If ($users.ContainsKey($memberDN)) {
                    $members += ((($users.$memberDN).UserPrincipalName) -replace '(.*)@(.*)','$2\$1').ToLower()
                }
                # If the member is a group, traverse that group
                ElseIf ($groups.ContainsKey($memberDN)) {
                    # Add the current group to the traversal list
                    $swallowReturn = $currentGroupList.Add($groupDN)
                    Get-Members $memberDN
                    $currentGroupList.Remove($groupDN)
                }
            }
            # Add the members found to the list of members for the group
            $explodedGroups.$groupDN += $members
        }
        
        # Add the members found in this group and to all groups previously traversed (parent groups)
        $currentMembers = $explodedGroups.$groupDN
        $currentGroupList | ForEach-Object {
            $groupDN = $_
            $groupMembers = $explodedGroups.$groupDN
            $groupMembers += $currentMembers
            $explodedGroups.$groupDN = $groupMembers
        }
    }
}

Function Process-GroupData {
    # Add group members to groups recursively
    $groups.Keys | ForEach-Object {
        $groupDN = $_
        $script:currentGroupList = New-Object System.Collections.ArrayList
        Get-Members $groupDN
    }
    # Add the users to their primary groups (e.g. Domain Users)
    $users.Values | ForEach-Object {
        ($explodedGroups.($_.PrimaryGroup)) += (($_.UserPrincipalName) -replace '(.*)@(.*)','$2\$1').ToLower()
    }
}

Function Write-XML {
    $XmlWriter = New-Object System.XMl.XmlTextWriter("$PSScriptRoot\GroupsAndMembers.xml",$Null)
    $xmlWriter.Formatting = 'Indented'
    $xmlWriter.Indentation = 4
    $XmlWriter.IndentChar = " "
    $XmlWriter.WriteStartDocument()
    $XmlWriter.WriteStartElement('uid-message')
    $xmlWriter.WriteElementString('version','1.0')
    $xmlWriter.WriteElementString('type','update')
    $XmlWriter.WriteStartElement('payload')
    $XmlWriter.WriteStartElement('groups')
    $groups.Values | ForEach-Object {
        $group = $_
        $groupDN = $group.DistinguishedName
        $groupName = $group.name
        $groupMembers = $explodedGroups.$groupDN
        $domain = $groupDN -replace '(.*?DC=)?(\w{1,}).*','$2'
        $XmlWriter.WriteStartElement('entry')
        $XmlWriter.WriteAttributeString('name',"$domain\$($group.name)".ToLower())
        $XmlWriter.WriteStartElement('members')
        $groupMembers | ForEach-Object {
            $member = $_
            $XmlWriter.WriteStartElement('entry')
            $XmlWriter.WriteAttributeString('name',$member)
            $XmlWriter.WriteEndElement();
        }
        $XmlWriter.WriteEndElement();
        $XmlWriter.WriteEndElement();
    }
    $XmlWriter.WriteEndElement();
    $XmlWriter.WriteEndElement();
    $XmlWriter.WriteEndDocument();
    $xmlWriter.Flush()
    $xmlWriter.Close()
}

Get-Date
$script:explodedGroups = @{}
Get-ADData
Process-GroupData
Write-XML
Get-Date

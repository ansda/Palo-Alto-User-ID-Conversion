# Script name:   nxlog patterndb helpder
# Created on:    12/31/2015
# Author:        Victor Carpetto

## Define Variables
$Path = "C:\Program Files (x86)\nxlog\conf\patterndb.xml"
$global:idx = 1

## Regex for UPN split / replace
$regexUPN = "(.*)@(.*)"

## Build AD Array of Objects
ipmo ActiveDirectory
$users = @()
$Domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
$Domain.Forest.Domains |
    % {
        $prefix = (Get-ADdomain $($_.name)).NetBIOSName + "\"
        $users += (Get-ADuser -filter {enabled -eq $true} -server "$($_.name):389") |
            select @{name="idx";expression = {($global:idx++)}},@{Name="domsam"; Expression = {($prefix + $_.samaccountname).tolower()}},@{Name="upn";Expression = {[regex]::replace($_.userprincipalname, $regexUPN, '$2\$1').tolower()}}
    }


## Write PatternDB
$xmlWriter = New-Object System.XMl.XmlTextWriter($Path,$Null)
$xmlWriter.Formatting = 'Indented'
$xmlWriter.Indentation = 1
$xmlWriter.IndentChar = "`t"
$xmlWriter.WriteStartDocument()
$xmlWriter.WriteComment('StartFile')
$xmlWriter.WriteStartElement('patterndb')
$xmlWriter.WriteElementString('version','1')
$xmlWriter.WriteStartElement('group')
$xmlWriter.WriteElementString('name','windows_eventlog')
$xmlWriter.WriteElementString('id','1')
$users | % {
    $xmlWriter.WriteStartElement('pattern')
        $xmlWriter.WriteElementString('id',$_.idx)
        $xmlWriter.WriteElementString('name','UserName')  
        $xmlWriter.WriteStartElement('matchfield')
            $xmlWriter.WriteElementString('name','DomSam')
            $xmlWriter.WriteElementString('type','exact')
            $xmlWriter.WriteElementString('value',$_.domsam)
        $xmlWriter.WriteEndElement()
        $xmlWriter.WriteStartElement('set')
            $xmlWriter.WriteStartElement('field')
                $xmlWriter.WriteElementString('name','UPN')
                $xmlWriter.WriteElementString('type','string')
                $xmlWriter.WriteElementString('value',$_.upn)
            $xmlWriter.WriteEndElement()
        $xmlWriter.WriteEndElement()
        $xmlWriter.WriteElementString('exec','if $UPN =~ /.*/ log_info("FOUND UPN: " + $UPN + " Source:" + $IpAddress);')
    $xmlWriter.WriteEndElement()
}
$xmlWriter.WriteEndElement()
$xmlWriter.WriteEndElement()
$xmlWriter.WriteEndDocument()
$xmlWriter.Flush()
$xmlWriter.Close()

## Cycle nxLog service and purge logs
Stop-Service nxlog -Verbose
rm L:\logs\eventlog.* -Verbose
rm "C:\Program Files (x86)\nxlog\data\nxlog.log" -Verbose
Start-Service nxlog -Verbose


$xmlWriter.WriteElementString('exec','if $UPN =~ /.*/ log_info("FOUND UPN: " + $UPN + " Source:" + $IpAddress);')

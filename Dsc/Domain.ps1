
configuration DomainConfig
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$DomainAdminCreds,

        [string]$datadriveLetter,
        [string]$TimeZone,

        [Int]$RetryCount = 20,
        [Int]$RetryIntervalSec = 30
    )

    Import-DscResource -ModuleName ComputerManagementdsc -ModuleVersion 8.2.0
    Import-DscResource -ModuleName StorageDSC -ModuleVersion 5.0.0
    Import-DscResource -ModuleName ActiveDirectoryDsc -ModuleVersion 6.0.1
    Import-DscResource -ModuleName ActiveDirectoryCSDsc -ModuleVersion 4.1.0.0
    Import-DscResource -ModuleName CertificateDSC -ModuleVersion 4.7.0.0

    Node localhost
    {
        # Set LCM to reboot if needed
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ActionafterReboot = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyOnly'
        }
        WaitForDisk DataVolume{
            DiskId = 2
            RetryIntervalSec = 60
            RetryCount =60
        }
#
        Disk DataVolume{
            DiskId =  2
            DriveLetter = $datadriveLetter
            FSFormat = 'NTFS'
            AllocationUnitSize = 64kb
            DependsOn = '[WaitForDisk]DataVolume'
        }

        File 'ADFiles'
        {
            Ensure = 'Present'
            DestinationPath = "$($datadriveLetter):\NTDS"
            Type = 'Directory'

            DependsOn = '[Disk]DataVolume'
        }

        WindowsFeature 'DNS'
        {
            Ensure = 'Present'
            Name = 'DNS'
        }

        WindowsFeature 'RSAT'
        {
            Ensure = 'Present'
            Name = 'RSAT'
        }

        WindowsFeature 'AD-Domain-Services'
        {
            Ensure = 'Present'
            Name = 'AD-Domain-Services'
            

            DependsOn = '[File]ADFiles'
        }

        WindowsFeature "RSAT-AD-AdminCenter"
        {
            Ensure = "Present"
            Name = "RSAT-AD-AdminCenter"
            DependsOn = "[WindowsFeature]AD-Domain-Services"
        }

        WindowsFeature 'RSAT-DNS-Server'
        {
            Ensure ='Present'
            Name = 'RSAT-DNS-Server'
        }

        WindowsFeature 'RSAT-AD-Tools'
        {
            Ensure = 'Present'
            Name = 'RSAT-AD-Tools'
        }

        WindowsFeature 'RSAT-ADDS'
        {
            Ensure = 'Present'
            Name = 'RSAT-ADDS'
        }

        WindowsFeature 'RSAT-ADDS-Tools'
        {
            Ensure = 'Present'
            Name = 'RSAT-ADDS-Tools'
        }

        TimeZone SetTimeZone
        {
            IsSingleInstance = 'Yes'
            TimeZone         = $TimeZone
        }

        ADDomain PrimaryDC
        {
            DomainName = $DomainName
            Credential = $DomainAdminCreds
            SafemodeAdministratorPassword = $DomainAdminCreds
            DatabasePath = "$($datadriveLetter):\NTDS"
            LogPath = "$($datadriveLetter):\NTDS"

            DependsOn  = '[WindowsFeature]AD-Domain-Services'
        }

        PendingReboot Reboot1
        {
            Name = 'Reboot1'
            dependson = '[ADDomain]PrimaryDC'
        }

        WaitforADDomain MyAD
        {
            DomainName = $DomainName
            Credential = $DomainAdminCreds  

            DependsOn ='[PendingReboot]Reboot1'
        }
        
        ADUser 'SqlUser'
        {
            Ensure = 'Present'
            DomainName = $DomainName
            UserName = 'SQLSvc'
            Password = $DomainAdminCreds

            DependsOn ='[WaitforADDomain]MyAD'
        }

        ADUser 'SqlAgent'
        {
            Ensure = 'Present'
            DomainName = $DomainName
            UserName = 'SQLAgt'
            Password = $DomainAdminCreds
        
            DependsOn ='[WaitforADDomain]MyAD'
        }

        ADUser 'Troy'
        {
            Ensure = 'Present'
            DomainName = $DomainName
            UserName = 'Troy'
            Password = $DomainAdminCreds
        
            DependsOn ='[WaitforADDomain]MyAD'
        }

        ADGroup 'DBA'
        {
            Ensure = 'Present'
            GroupName = 'DBA'
            GroupScope = 'Global'
            Category = 'Security'
            MembersToInclude = 'Troy'
            
            DependsOn ='[WaitforADDomain]MyAD'
        }

        WindowsFeature 'ADCS-Cert-Authority'
        {
               Ensure = 'Present'
               Name = 'ADCS-Cert-Authority'

               DependsOn ='[WaitforADDomain]MyAD'
        }

        ADCSCertificationAuthority 'ADCS'
        {
            Ensure = 'Present'
            IsSingleInstance = 'Yes'
            Credential = $DomainAdminCreds
            CAType = 'EnterpriseRootCA'
            DependsOn = '[WindowsFeature]ADCS-Cert-Authority'              
        }
        WindowsFeature ADCS-Web-Enrollment
        {
            Ensure = 'Present'
            Name   = 'ADCS-Web-Enrollment'
        }

        AdcsWebEnrollment WebEnrollment
        {
            Ensure           = 'Present'
            IsSingleInstance = 'Yes'
            Credential       = $DomainAdminCreds
            DependsOn        = '[WindowsFeature]ADCS-Web-Enrollment','[ADCSCertificationAuthority]ADCS','[WindowsFeature]ADCS-Cert-Authority'
        }

        WindowsFeature ADCS-Enroll-Web-Pol
        {
            Ensure = 'Present'
            Name   = 'ADCS-Enroll-Web-Pol'

            DependsOn = '[AdcsWebEnrollment]WebEnrollment'
        }
        
        WindowsFeature RSAT-ADCS
        {
            Ensure = 'Present'
            Name   = 'RSAT-ADCS'

            DependsOn = '[AdcsWebEnrollment]WebEnrollment'
        }
        
        WindowsFeature RSAT-ADCS-Mgmt
        {
            Ensure = 'Present'
            Name   = 'RSAT-ADCS-Mgmt'

            DependsOn = '[AdcsWebEnrollment]WebEnrollment'
        }
    }
}
 
$ConfigData = @{
    AllNodes = @(
    @{
        NodeName = 'localhost'
        PSDscAllowPlainTextPassword = $true
    }
    )
}

# $DomainAdminCreds = Get-Credential
# $CertificateThumbprint =$(Get-AzKeyVaultCertificate -VaultName $VaultName -Name $CertName).Thumbprint
# DomainConfig -DomainName demolab.local -DomainAdminCreds $DomainAdminCreds -datadriveLetter "F" -TimeZone "Eastern Standard Time" -Verbose -ConfigurationData $ConfigData -OutputPath C:\Packages\Plugins\Microsoft.Powershell.DSC\2.80.0.0\DSCWork\Domain.0\DomainConfig
# Start-DscConfiguration -wait -Force -Verbose -Path C:\Packages\Plugins\Microsoft.Powershell.DSC\2.80.0.0\DSCWork\Domain.0\DomainConfig


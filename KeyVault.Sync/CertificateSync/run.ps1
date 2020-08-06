# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

$PfxPassword = ([guid]::NewGuid()).Guid
$PfxPasswordSecure = ConvertTo-SecureString -String $PfxPassword -AsPlainText -Force


$SourceTenant = $env:SourceTenant
$SourceClientId = $env:SourceClientId
$SourceClientSecret = $env:SourceClientSecret
$SourceKeyVault = $env:SourceKeyVault

$TargetTenant = $env:TargetTenant
$TargetClientId = $env:TargetClientId
$TargetClientSecret = $env:TargetClientSecret
$TargetKeyVault = $env:TargetKeyVault

$SourceCredential = New-Object -TypeName System.Management.Automation.PSCredential($SourceClientId, (ConvertTo-SecureString -String $SourceClientSecret -AsPlainText -Force))
$SourceAccount = Connect-AzAccount -Credential $SourceCredential -Tenant $SourceTenant -ServicePrincipal

$TargetCredential = New-Object -TypeName System.Management.Automation.PSCredential($TargetClientId, (ConvertTo-SecureString -String $TargetClientSecret -AsPlainText -Force))
$TargetAccount = Connect-AzAccount -Credential $TargetCredential -Tenant $TargetTenant -ServicePrincipal

$null = Set-AzContext -Context $SourceAccount.Context
Get-AzKeyVaultCertificate -VaultName $SourceKeyVault | ForEach-Object { 
    $CertName = $_.Name 
    
    $null = Set-AzContext -Context $SourceAccount.Context
    $SourceCert = Get-AzKeyVaultCertificate -VaultName $SourceKeyVault -Name $CertName 
    
    $null = Set-AzContext -Context $TargetAccount.Context
    $TargetCert = Get-AzKeyVaultCertificate -VaultName $TargetKeyVault -Name $CertName 
    
    if (!($TargetCert) -or ($TargetCert.Updated -lt $SourceCert.Updated)) 
    { 
        Write-Verbose -Message "Cert: $CertName will be updated" -Verbose 
        $null = Set-AzContext -Context $SourceAccount.Context
        $SourceSecret = Get-AzKeyVaultSecret -VaultName $SourceKeyVault -Name $SourceCert.Name
        $secretByte = [Convert]::FromBase64String($SourceSecret.SecretValueText)
        $x509Cert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2($secretByte, "", "Exportable,PersistKeySet")
        $type = [System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx
        $pfxFileByte = $x509Cert.Export($type, $PfxPassword)
        [System.IO.File]::WriteAllBytes("$CertName.pfx", $pfxFileByte)

        $null = Set-AzContext -Context $TargetAccount.Context
        $null = Import-AzKeyVaultCertificate -VaultName $TargetKeyVault -Name $CertName -FilePath "$CertName.pfx" -Password $PfxPasswordSecure
        
        $null = Remove-Item -Path "$CertName.pfx"
    } 
    else 
    { 
        Write-Verbose -Message "Cert: $CertName already up to date" -Verbose 
    } 
}
if (Test-Path "$PSScriptRoot\Sitecore.Cloud.Cmdlets.dll") {
  Import-Module "$PSScriptRoot\Sitecore.Cloud.Cmdlets.dll"
}
elseif (Test-Path "$PSScriptRoot\bin\Sitecore.Cloud.Cmdlets.dll") {
  Import-Module "$PSScriptRoot\bin\Sitecore.Cloud.Cmdlets.dll"
}
else {
  throw "Failed to find Sitecore.Cloud.Cmdlets.dll, searched $PSScriptRoot and $PSScriptRoot\bin"
}

# public functions
Function Start-SitecoreAzureDeployment{
    <#
        .SYNOPSIS
        You can deploy a new Sitecore instance on Azure for a specific SKU

        .DESCRIPTION
        Deploys a new instance of Sitecore on Azure

        .PARAMETER location
        Standard Azure region (e.g.: North Europe)
        .PARAMETER Name
        Name of the deployment
        .PARAMETER ArmTemplateUrl
        Url to the ARM template
        .PARAMETER ArmTemplatePath
        Path to the ARM template
        .PARAMETER ArmParametersPath
        Path to the ARM template parameter
        .PARAMETER LicenseXmlPath
        Path to a valid Sitecore license
        .PARAMETER SetKeyValue
        This is a hash table, use to set the unique values for the deployment parameters in Arm Template Parameters Json

        .EXAMPLE
        Import-Module -Verbose .\Cloud.Services.Provisioning.SDK\tools\Sitecore.Cloud.Cmdlets.psm1
        $SetKeyValue = @{
        "deploymentId"="xP0-QA";
        "Sitecore.admin.password"="!qaz2wsx";
        "sqlserver.login"="xpsqladmin";
        "sqlserver.password"="Password12345";    "analytics.mongodb.connectionstring"="mongodb://17.54.72.145:27017/xP0-QA-analytics";
        "tracking.live.mongodb.connectionstring"="mongodb://17.54.72.145:27017/xP0-QA-tracking_live";
        "tracking.history.mongodb.connectionstring"="mongodb://17.54.72.145:27017/xP0-QA-tracking_history";
        "tracking.contact.mongodb.connectionstring"="mongodb://17.54.72.145:27017/xP0-QA-tracking_contact"
        }
        Start-SitecoreAzureDeployment -Name $SetKeyValue.deploymentId -Region "North Europe" -ArmTemplatePath "C:\dev\azure\xP0.Template.json" -ArmParametersPath "xP0.Template.params.json" -LicenseXmlPath "D:\xp0\license.xml" -SetKeyValue $SetKeyValue
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [alias("Region")]
        [string]$Location,
        [parameter(Mandatory=$true)]
        [string]$Name,
        [parameter(ParameterSetName="Template URI", Mandatory=$true)]
        [string]$ArmTemplateUrl,
        [parameter(ParameterSetName="Template Path", Mandatory=$true)]
        [string]$ArmTemplatePath,
        [parameter(Mandatory=$true)]
        [string]$ArmParametersPath,
        [parameter(Mandatory=$true)]
        [string]$LicenseXmlPath,
        [hashtable]$SetKeyValue
    )

    try {
        Write-Host "Deployment Started..."

        if ([string]::IsNullOrEmpty($ArmTemplateUrl) -and [string]::IsNullOrEmpty($ArmTemplatePath)) {
            Write-Host "Either ArmTemplateUrl or ArmTemplatePath is required!"
            Break
        }

        if(!($Name -cmatch '^(?!.*--)[a-z0-9]{2}(|([a-z0-9\-]{0,37})[a-z0-9])$'))
        {
            Write-Error "Name should only contain lowercase letters, digits or dashes,
                         dash cannot be used in the first two or final character,
                         it cannot contain consecutive dashes and is limited between 2 and 40 characters in length!"
            Break;
        }

        if ($SetKeyValue -eq $null) {
            $SetKeyValue = @{}
        }

        # Set the Parameters in Arm Template Parameters Json
        $paramJson = Get-Content $ArmParametersPath -Raw

        Write-Verbose "Setting ARM template parameters..."
        
        # Read and Set the license.xml
        $licenseXml = Get-Content $LicenseXmlPath -Raw -Encoding UTF8
        $SetKeyValue.Add("licenseXml", $licenseXml)

        # Update params and save to a temporary file
        $paramJsonFile = "temp_$([System.IO.Path]::GetRandomFileName())"
        Set-SCAzureDeployParameters -ParametersJson $paramJson -SetKeyValue $SetKeyValue | Set-Content $paramJsonFile -Encoding UTF8

        Write-Verbose "ARM template parameters are set!"

        # Deploy Sitecore in given Location
        Write-Verbose "Deploying Sitecore Instance..."
        $notPresent = Get-AzResourceGroup -Name $Name -ev notPresent -ea 0
        if (!$notPresent) {
            New-AzResourceGroup -Name $Name -Location $Location -Tag @{ "provider" = "b51535c2-ab3e-4a68-95f8-e2e3c9a19299" }
        }
        else {
            Write-Verbose "Resource Group Already Exists."
        }

        if ([string]::IsNullOrEmpty($ArmTemplateUrl)) {
            $PSResGrpDeployment = New-AzResourceGroupDeployment -Name $Name -ResourceGroupName $Name -TemplateFile $ArmTemplatePath -TemplateParameterFile $paramJsonFile
        }else{
            # Replace space character in the url, as it's not being replaced by the cmdlet itself
            $PSResGrpDeployment = New-AzResourceGroupDeployment -Name $Name -ResourceGroupName $Name -TemplateUri ($ArmTemplateUrl -replace ' ', '%20') -TemplateParameterFile $paramJsonFile
        }
        $PSResGrpDeployment
    }
    catch {
        Write-Error $_.Exception.Message
        Break
    }
    finally {
      if ($paramJsonFile) {
        Remove-Item $paramJsonFile
      }
    }
}

Function Start-SitecoreAzurePackaging{
    <#
        .SYNOPSIS
        Using this command you can create SKU specific Sitecore Azure web deploy packages

        .DESCRIPTION
        Creates valid Azure web deploy packages for SKU specified in the sku configuration file

        .PARAMETER sitecorePath
        Path to the Sitecore's zip file
        .PARAMETER destinationFolderPath
        Destination folder path which web deploy packages will be generated into
        .PARAMETER cargoPayloadFolderPath
        Path to the root folder containing cargo payloads (*.sccpl files)
        .PARAMETER commonConfigPath
        Path to the common.packaging.config.json file
        .PARAMETER skuConfigPath
        Path to the sku specific config file (e.g.: xp1.packaging.config.json)
        .PARAMETER parameterXmlPath
        Path to the root folder containing MS Deploy xml files (parameters.xml)
        .PARAMETER fileVersion
        Generates a text file called version.txt, containing value passed to this parameter and puts it in the webdeploy package for traceability purposes - this parameter is optional
        .PARAMETER integratedSecurity
        Indicates should integrated security be used in connectionString. False by default

        .EXAMPLE
        Start-SitecoreAzurePackaging -sitecorePath "C:\Sitecore\Sitecore 8.2 rev. 161103.zip" ` -destinationFolderPath .\xp1 `
        -cargoPayloadFolderPath .\Cloud.Services.Provisioning.SDK\tools\CargoPayloads `
        -commonConfigPath .\Cloud.Services.Provisioning.SDK\tools\Configs\common.packaging.config.json `
        -skuConfigPath .\Cloud.Services.Provisioning.SDK\tools\Configs\xp1.packaging.config.json `
        -parameterXmlPath .\Cloud.Services.Provisioning.SDK\tools\MSDeployXmls
        -integratedSecurity $true
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [string]$SitecorePath,
        [parameter(Mandatory=$true)]
        [string]$DestinationFolderPath,
        [parameter(Mandatory=$true)]
        [string]$CargoPayloadFolderPath,
        [parameter(Mandatory=$true)]
        [string]$CommonConfigPath,
        [parameter(Mandatory=$true)]
        [string]$SkuConfigPath,
        [parameter(Mandatory=$true)]
        [string]$ParameterXmlPath,
        [parameter(Mandatory=$false)]
        [string]$FileVersion,
        [parameter(Mandatory=$false)]
        [bool]$IntegratedSecurity
    )

    try {

        $DestinationFolderPath = AddTailBackSlashToPathIfNotExists($DestinationFolderPath)
        $cargoPayloadFolderPath = AddTailBackSlashToPathIfNotExists($CargoPayloadFolderPath)
        $ParameterXmlPath = AddTailBackSlashToPathIfNotExists($ParameterXmlPath)

        # Create the Raw Web Deploy Package
        Write-Verbose "Creating the Raw Web Deploy Package..."
        if ($FileVersion -eq $null) {
                $sitecoreWebDeployPackagePath = New-SCWebDeployPackage -Path $SitecorePath -Destination $DestinationFolderPath -IntegratedSecurity $IntegratedSecurity
        }
        else {
                $sitecoreWebDeployPackagePath = New-SCWebDeployPackage -Path $SitecorePath -Destination $DestinationFolderPath -FileVersion $FileVersion -IntegratedSecurity $IntegratedSecurity -Force
        }
        Write-Verbose "Raw Web Deploy Package Created Successfully!"

        # Read and Apply the common Configs
        $commonConfigs = (Get-Content $CommonConfigPath -Raw) | ConvertFrom-Json
        $commonSccplPaths = @()
        foreach($sccpl in $commonConfigs.sccpls)
        {
            $commonSccplPaths += $CargoPayloadFolderPath + $sccpl;
        }

        Write-Verbose "Applying Common Cloud Configurations..."
        Update-SCWebDeployPackage -Path $sitecoreWebDeployPackagePath -CargoPayloadPath $commonSccplPaths
        Write-Verbose "Common Cloud Configurations Applied Successfully!"

        # Read the SKU Configs
        $skuconfigs = (Get-Content $SkuConfigPath -Raw) | ConvertFrom-Json
        foreach($scwdp in $skuconfigs.scwdps)
        {
            # Create the role specific scwdps
            $roleScwdpPath =  $sitecoreWebDeployPackagePath -replace ".scwdp", ("_" + $scwdp.role + ".scwdp")
            Copy-Item $sitecoreWebDeployPackagePath $roleScwdpPath -Verbose

            # Apply the role specific cargopayloads
            $sccplPaths = @()
            foreach($sccpl in $scwdp.sccpls)
            {
                $sccplPaths += $CargoPayloadFolderPath + $sccpl;
            }
            if ($sccplPaths.Length -gt 0) {
                Write-Verbose "Applying $($scwdp.role) Role Specific Configurations..."
                Update-SCWebDeployPackage -Path $roleScwdpPath -CargoPayloadPath $sccplPaths
                Write-Verbose "$($scwdp.role) Role Specific Configurations Applied Successfully!"
            }

            # Set the role specific parameters.xml and archive.xml
            Write-Verbose "Setting $($scwdp.role) Role Specific Web Deploy Package Parameters XML and Generating Archive XML..."
            Update-SCWebDeployPackage -Path $roleScwdpPath -ParametersXmlPath ($ParameterXmlPath + $scwdp.parametersXml)
            Write-Verbose "$($scwdp.role) Role Specific Web Deploy Package Parameters and Archive XML Added Successfully!"
        }

        # Remove the Raw Web Deploy Package
        Remove-Item -Path $sitecoreWebDeployPackagePath
    }
    catch {
        Write-Host $_.Exception.Message
        Break
    }
}

Function Start-SitecoreAzureModulePackaging {
    <#
        .SYNOPSIS
        Using this command you can create Sitecore Azure Module web deploy packages

        .DESCRIPTION
        Creates valid Sitecore Azure Module web deploy packages

        .PARAMETER SourceFolderPath
        Source folder path to the Sitecore's exm module package zip files

        .PARAMETER DestinationFolderPath
        Destination folder path which web deploy packages will be generated into

        .PARAMETER CargoPayloadFolderPath
        Root folder path which contain cargo payloads (*.sccpl files)

		.PARAMETER AdditionalWdpContentsFolderPath
        Root folder path which contain folders with additional contents to Wdp

        .PARAMETER ParameterXmlPath
        Root folder path which contain the msdeploy xml files (parameters.xml)

        .PARAMETER ConfigFilePath
        File path of SKU and Role config json files

        .EXAMPLE
		Start-SitecoreAzureModulePackaging -SourceFolderPath "D:\Sitecore\Modules\Email Experience Manager 3.5.0 rev. 170310" -DestinationFolderPath "D:\Work\EXM\WDPs" -CargoPayloadFolderPath "D:\Resources\EXM 3.5\CargoPayloads" -AdditionalWdpContentsFolderPath "D:\Work\EXM\AdditionalFiles" -ParameterXmlFolderPath "D:\Resources\EXM 3.5\MsDeployXmls" -ConfigFile "D:\Resources\EXM 3.5\Configs\EXM0.Packaging.config.json"
    #>

    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [string]$SourceFolderPath,
        [parameter(Mandatory=$true)]
        [string]$DestinationFolderPath,
        [parameter(Mandatory=$true)]
        [string]$CargoPayloadFolderPath,
		[parameter(Mandatory=$true)]
        [string]$AdditionalWdpContentsFolderPath,
        [parameter(Mandatory=$true)]
        [string]$ParameterXmlFolderPath,
        [parameter(Mandatory=$true)]
        [string]$ConfigFilePath
    )

    # Read the role config
    $skuconfigs = (Get-Content $ConfigFilePath -Raw) | ConvertFrom-Json
    ForEach($scwdp in $skuconfigs.scwdps) {

        # Find source package path
        Get-ChildItem $SourceFolderPath | Where-Object { $_.Name -match $scwdp.sourcePackagePattern } |
        Foreach-Object {
            $packagePath = $_.FullName
        }

        # Create the Wdp
        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $packagePath -Destination $DestinationFolderPath

        # Apply the Cargo Payloads
        ForEach($sccpl in $scwdp.sccpls) {
            $cargoPayloadPath = $sccpl
            Update-SCWebDeployPackage -Path $wdpPath -CargoPayloadPath "$CargoPayloadFolderPath\$cargoPayloadPath"
        }

        # Embed the Cargo Payloads
        ForEach($embedSccpl in $scwdp.embedSccpls) {
            $embedCargoPayloadPath = $embedSccpl
            Update-SCWebDeployPackage -Path $wdpPath -EmbedCargoPayloadPath "$CargoPayloadFolderPath\$embedCargoPayloadPath"
        }

		# Add additional Contents To Wdp from given Folders
		ForEach($additionalContentFolder in $scwdp.additionalWdpContentsFolders) {
			$additionalContentsFolderPath = $additionalContentFolder
			Update-SCWebDeployPackage -Path $wdpPath -SourcePath "$AdditionalWdpContentsFolderPath\$additionalContentsFolderPath"
		}

		# Update the ParametersXml
		if($scwdp.parametersXml) {
			$parametersXml = $scwdp.parametersXml
			Update-SCWebDeployPackage -Path $wdpPath -ParametersXmlPath "$ParameterXmlFolderPath\$parametersXml"
		}

        # Rename the Wdp to be more role specific
        $role = $scwdp.role
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_$role.scwdp.zip")
    }
}

Function ConvertTo-SitecoreWebDeployPackage {
    <#
        .SYNOPSIS
        Using this command, you can convert a Sitecore package to a web deploy package

        .DESCRIPTION
        Creates a new webdeploypackage from the Sitecore package passed to it

        .PARAMETER Path
        Path to the Sitecore installer package
        .PARAMETER Destination
        Destination folder that web deploy package will be created into - optional parameter, if not passed will use the current location
        .PARAMETER Force
        If set, will overwrite existing web deploy package with the same name

        .EXAMPLE
        ConvertTo-SitecoreWebDeployPackage -Path "C:\Sitecore\Modules\Web Forms for Marketers 8.2 rev. 160801.zip" -Force

        .REMARKS
        Currently, this CmdLet creates a webdeploy package only from "files" folder of the package
    #>
    [Obsolete("Use Start-SitecoreAzureModulePackaging for Sitecore module packaging")]
    [CmdletBinding()]
    param(
    [parameter(Mandatory=$true)]
    [string]$Path,
    [parameter()]
    [string]$Destination,
    [parameter()]
    [switch]$Force
    )

    if(!$Destination -or $Destination -eq "") {
        $Destination = (Get-Location).Path
    }

    if($Force) {
        return ConvertTo-SCWebDeployPackage -PSPath $Path -Destination $Destination -Force
    } else {
        return ConvertTo-SCWebDeployPackage -PSPath $Path -Destination $Destination
    }
}

Function Set-SitecoreAzureTemplates {
    <#
        .SYNOPSIS
        Using this command you can upload Sitecore ARM templates to an Azure Storage

        .DESCRIPTION
        Uploads all the ARM Templates files in the given folder and the sub folders to given Azure Storage in the same folder hierarchy

        .PARAMETER Path
        Path to the Sitecore ARM Templates folder
        .PARAMETER StorageContainerName
        Name of the target container in the Azure Storage Account
        .PARAMETER AzureStorageContext
        Azure Storage Context object returned by New-AzureStorageContext
        .PARAMETER StorageConnectionString
        Connection string of the target Azure Storage Account
        .PARAMETER Force
        If set, will overwrite existing templates with the same name in the target container

        .EXAMPLE
        $StorageContext = New-AzStorageContext -StorageAccountName "samplestorageaccount" -StorageAccountKey "3pQEA23emk0aio2RK6luL0MfP2P81lg9JEo4gHSEHkejL9+/9HCU4IjhsgAbcXnQz6j72B3Xq8TZZpwj4GI+Qw=="
        Set-SitecoreAzureTemplates -Path "D:\Work\UploadSitecoreTemplates\Templates" -StorageContainerName "samplecontainer" -AzureStorageContext $StorageContext
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]$Path,
        [parameter(Mandatory=$true)]
        [string]$StorageContainerName,
        [parameter(ParameterSetName="context",Mandatory=$true)]
        [System.Object]$AzureStorageContext,
        [parameter(ParameterSetName="connstring",Mandatory=$true)]
        [string]$StorageConnectionString,
        [parameter()]
        [switch]$Force
    )

    if ([string]::IsNullOrEmpty($StorageConnectionString) -and ($AzureStorageContext -eq $null)) {
        Write-Host "Either StorageConnectionString or AzureStorageContext is required!"
        Break
    }

    if ($StorageConnectionString) {
        $AzureStorageContext = New-AzStorageContext -ConnectionString $StorageConnectionString
    }

    $absolutePath = Resolve-Path -Path $Path
    $absolutePath = AddTailBackSlashToPathIfNotExists($absolutePath)

    $urlList = @()
    $files = Get-ChildItem $Path -Recurse -Filter "*.json"

    foreach($file in $files)
    {
        $localFile = $file.FullName
        $blobFile = $file.FullName.Replace($absolutePath, "")

        if ($Force) {
            $blobInfo = Set-AzStorageBlobContent -File $localFile -Container $StorageContainerName -Blob $blobFile -Context $AzureStorageContext -Force
        } else{
            $blobInfo = Set-AzStorageBlobContent -File $localFile -Container $StorageContainerName -Blob $blobFile -Context $AzureStorageContext
        }

        $urlList += $blobInfo.ICloudBlob.uri.AbsoluteUri
    }

    return ,$urlList
}

# Export public functions
Export-ModuleMember -Function Start-SitecoreAzureDeployment
Export-ModuleMember -Function Start-SitecoreAzurePackaging
Export-ModuleMember -Function Start-SitecoreAzureModulePackaging
Export-ModuleMember -Function ConvertTo-SitecoreWebDeployPackage
Export-ModuleMember -Function Set-SitecoreAzureTemplates
Export-ModuleMember -Cmdlet New-SCCargoPayload

# Internal functions
Function AddTailBackSlashToPathIfNotExists {
 param( [string]$Path)

    $Path = $Path.Trim()
    if (!$Path.EndsWith("\"))
    {
        $Path = $Path + "\"
    }

    return $Path
}

# SIG # Begin signature block
# MIImLwYJKoZIhvcNAQcCoIImIDCCJhwCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCUxhhuNQNA75j/
# gVOKjmyk8YYOhAbydxhHvFjo4LvM66CCFBUwggWQMIIDeKADAgECAhAFmxtXno4h
# MuI5B72nd3VcMA0GCSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0xMzA4MDExMjAwMDBaFw0z
# ODAxMTUxMjAwMDBaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0
# IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# AL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/z
# G6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZ
# anMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7s
# Wxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL
# 2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfb
# BHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3
# JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3c
# AORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqx
# YxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0
# viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aL
# T8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjQjBAMA8GA1Ud
# EwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgGGMB0GA1UdDgQWBBTs1+OC0nFdZEzf
# Lmc/57qYrhwPTzANBgkqhkiG9w0BAQwFAAOCAgEAu2HZfalsvhfEkRvDoaIAjeNk
# aA9Wz3eucPn9mkqZucl4XAwMX+TmFClWCzZJXURj4K2clhhmGyMNPXnpbWvWVPjS
# PMFDQK4dUPVS/JA7u5iZaWvHwaeoaKQn3J35J64whbn2Z006Po9ZOSJTROvIXQPK
# 7VB6fWIhCoDIc2bRoAVgX+iltKevqPdtNZx8WorWojiZ83iL9E3SIAveBO6Mm0eB
# cg3AFDLvMFkuruBx8lbkapdvklBtlo1oepqyNhR6BvIkuQkRUNcIsbiJeoQjYUIp
# 5aPNoiBB19GcZNnqJqGLFNdMGbJQQXE9P01wI4YMStyB0swylIQNCAmXHE/A7msg
# dDDS4Dk0EIUhFQEI6FUy3nFJ2SgXUE3mvk3RdazQyvtBuEOlqtPDBURPLDab4vri
# RbgjU2wGb2dVf0a1TD9uKFp5JtKkqGKX0h7i7UqLvBv9R0oN32dmfrJbQdA75PQ7
# 9ARj6e/CVABRoIoqyc54zNXqhwQYs86vSYiv85KZtrPmYQ/ShQDnUBrkG5WdGaG5
# nLGbsQAe79APT0JsyQq87kP6OnGlyE0mpTX9iV28hWIdMtKgK1TtmlfB2/oQzxm3
# i0objwG2J5VT6LaJbVu8aNQj6ItRolb58KaAoNYes7wPD1N1KarqE3fk3oyBIa0H
# EEcRrYc9B9F1vM/zZn4wggawMIIEmKADAgECAhAIrUCyYNKcTJ9ezam9k67ZMA0G
# CSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0
# IFRydXN0ZWQgUm9vdCBHNDAeFw0yMTA0MjkwMDAwMDBaFw0zNjA0MjgyMzU5NTla
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEz
# ODQgMjAyMSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDVtC9C
# 0CiteLdd1TlZG7GIQvUzjOs9gZdwxbvEhSYwn6SOaNhc9es0JAfhS0/TeEP0F9ce
# 2vnS1WcaUk8OoVf8iJnBkcyBAz5NcCRks43iCH00fUyAVxJrQ5qZ8sU7H/Lvy0da
# E6ZMswEgJfMQ04uy+wjwiuCdCcBlp/qYgEk1hz1RGeiQIXhFLqGfLOEYwhrMxe6T
# SXBCMo/7xuoc82VokaJNTIIRSFJo3hC9FFdd6BgTZcV/sk+FLEikVoQ11vkunKoA
# FdE3/hoGlMJ8yOobMubKwvSnowMOdKWvObarYBLj6Na59zHh3K3kGKDYwSNHR7Oh
# D26jq22YBoMbt2pnLdK9RBqSEIGPsDsJ18ebMlrC/2pgVItJwZPt4bRc4G/rJvmM
# 1bL5OBDm6s6R9b7T+2+TYTRcvJNFKIM2KmYoX7BzzosmJQayg9Rc9hUZTO1i4F4z
# 8ujo7AqnsAMrkbI2eb73rQgedaZlzLvjSFDzd5Ea/ttQokbIYViY9XwCFjyDKK05
# huzUtw1T0PhH5nUwjewwk3YUpltLXXRhTT8SkXbev1jLchApQfDVxW0mdmgRQRNY
# mtwmKwH0iU1Z23jPgUo+QEdfyYFQc4UQIyFZYIpkVMHMIRroOBl8ZhzNeDhFMJlP
# /2NPTLuqDQhTQXxYPUez+rbsjDIJAsxsPAxWEQIDAQABo4IBWTCCAVUwEgYDVR0T
# AQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUaDfg67Y7+F8Rhvv+YXsIiGX0TkIwHwYD
# VR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNV
# HR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkUm9vdEc0LmNybDAcBgNVHSAEFTATMAcGBWeBDAEDMAgGBmeBDAEEATAN
# BgkqhkiG9w0BAQwFAAOCAgEAOiNEPY0Idu6PvDqZ01bgAhql+Eg08yy25nRm95Ry
# sQDKr2wwJxMSnpBEn0v9nqN8JtU3vDpdSG2V1T9J9Ce7FoFFUP2cvbaF4HZ+N3HL
# IvdaqpDP9ZNq4+sg0dVQeYiaiorBtr2hSBh+3NiAGhEZGM1hmYFW9snjdufE5Btf
# Q/g+lP92OT2e1JnPSt0o618moZVYSNUa/tcnP/2Q0XaG3RywYFzzDaju4ImhvTnh
# OE7abrs2nfvlIVNaw8rpavGiPttDuDPITzgUkpn13c5UbdldAhQfQDN8A+KVssIh
# dXNSy0bYxDQcoqVLjc1vdjcshT8azibpGL6QB7BDf5WIIIJw8MzK7/0pNVwfiThV
# 9zeKiwmhywvpMRr/LhlcOXHhvpynCgbWJme3kuZOX956rEnPLqR0kq3bPKSchh/j
# wVYbKyP/j7XqiHtwa+aguv06P0WmxOgWkVKLQcBIhEuWTatEQOON8BUozu3xGFYH
# Ki8QxAwIZDwzj64ojDzLj4gLDb879M4ee47vtevLt/B3E+bnKD+sEq6lLyJsQfmC
# XBVmzGwOysWGw/YmMwwHS6DTBwJqakAwSEs0qFEgu60bhQjiWQ1tygVQK+pKHJ6l
# /aCnHwZ05/LWUpD9r4VIIflXO7ScA+2GRfS0YW6/aOImYIbqyK+p/pQd52MbOoZW
# eE4wggfJMIIFsaADAgECAhAOWDArdt3BhOzKi4Ks/8bnMA0GCSqGSIb3DQEBCwUA
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEz
# ODQgMjAyMSBDQTEwHhcNMjIxMDE3MDAwMDAwWhcNMjMxMTAzMjM1OTU5WjCBqTEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCkNhbGlmb3JuaWExFjAUBgNVBAcTDVNhbiBG
# cmFuY2lzY28xGzAZBgNVBAoTElNpdGVjb3JlIFVTQSwgSW5jLjELMAkGA1UECxMC
# SVQxGzAZBgNVBAMTElNpdGVjb3JlIFVTQSwgSW5jLjEmMCQGCSqGSIb3DQEJARYX
# aWx5YS5kaW1vdkBzaXRlY29yZS5jb20wggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQDSpDYiWgzsojERrPzBfBwEfHquos9XObg7LfQUlikKxMJzxWrxldMT
# 1Wo4VN7O6jB9A2BwxR7f/mLkUT9N8oTzP0VMxqs0S13tQpEZ/ZqlRtfBp9A+4Fp1
# mviP0GlYlZ1O4zkKBh/EfccNcKpemmexirs8bW/pvRal1hVKPL47R5Zs9UNsY3oT
# ocnbtSWb4CTKFupCi8jAFsKGluZTOLTZ1m3rXcYuYEVnsnaw04h1n1xABce/2Ajj
# TGFbN/j30dUVfHuIfAF45WQy70mPEksp/vKhbckUhJ9Jnuc3dP5x5WHz2WO7+zjt
# qLylI0Wz+DlL3UhNtgv1HOYL8vc8l1/NvKLhlIWODjmcyT9zza2LMapdC2KdncU7
# 5nvJbWGnSJDan6ego57mikUhmXGMJbPy4RdgJjTFhdzuRL89nf+TWZ0F85RAR/HM
# 4bMgjgYaxwKuxxM5Hb3L8X146gThR8QxVQSLpE1CJU86afELMbZTJiZ32k7jH1fl
# WoGwNwhc1KMCz1Y0cLEmIj8fmdHRVulZIOVxGxCfgSdeBoylUVUFkc9Mpm/Xilx7
# XRPRIu+Jp3nYW8gCK/aKSdoIyfAMNee7dmIFR0kjtpWnn33pu111mt6OtCF6XHE9
# kNRaY+mL+q1WTuXme6H8jR3yjt35kjtKO1SH4OBBUZW2OWprzw6lNQIDAQABo4IC
# KjCCAiYwHwYDVR0jBBgwFoAUaDfg67Y7+F8Rhvv+YXsIiGX0TkIwHQYDVR0OBBYE
# FBAH6bDYbTkLp29ACivpdh6zuoSyMCIGA1UdEQQbMBmBF2lseWEuZGltb3ZAc2l0
# ZWNvcmUuY29tMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzCB
# tQYDVR0fBIGtMIGqMFOgUaBPhk1odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGln
# aUNlcnRUcnVzdGVkRzRDb2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNy
# bDBToFGgT4ZNaHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3Rl
# ZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAyMUNBMS5jcmwwPgYDVR0gBDcw
# NTAzBgZngQwBBAEwKTAnBggrBgEFBQcCARYbaHR0cDovL3d3dy5kaWdpY2VydC5j
# b20vQ1BTMIGUBggrBgEFBQcBAQSBhzCBhDAkBggrBgEFBQcwAYYYaHR0cDovL29j
# c3AuZGlnaWNlcnQuY29tMFwGCCsGAQUFBzAChlBodHRwOi8vY2FjZXJ0cy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRDb2RlU2lnbmluZ1JTQTQwOTZTSEEz
# ODQyMDIxQ0ExLmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4ICAQC4
# FI/hctFLM03rjO/8b1+Z6PCFlXFz/Tsdx/d7b9Gwn+z1fpuhZ5WCURExoPRJdjMr
# qCOoG/qdtXptPHpZvYLgELSlHh/oGJqbybeF5DUIaqvCswEgMgS/TnkhE4miXU7H
# YTxLXfLzHvPxsCWoWK+tVfq6/qGxecjj0yov2MXFjCSEBFoNrX33BlwK8z+G6ZeX
# DFue8XGrb/hz3jfw0B/TN6LWmNqgfwpBJOsbLWogz5Fvoh3B1M1Z1FcrtVKI9ffZ
# MaV64xKntFzGF0dc3XN3G/3pFCZlXEA2e61Pia6Zm8DzeVa0SKE4dHUunE6CXyKO
# iKL/dgNxxTkHgzyMKXT9oZcN/8lLatew/OUP0fi7XHWqulkMKnPhiDT0hLHXbdaq
# Q+9W838rG5Fj2xwK/wv5DFbVl2/BieGjYAqA2mrNvrcChpy/G9kkrpDvTPaXJ8GK
# sCOrRbpLxVkkf6Hl/IWPdvy0NwprFELZSzAbPQCfSDMWhM1GI5dACs3YcfRtrtzC
# /Ght0L8U7SKVG0A+yinkQ5h2IikQetxojALQArf/+0XDZXXu4h1B1Lp6WgGvzUyV
# C3SuE4ssMGLinXKDXy2P90dGBCuCqSXxANFBL3Iqg/E7s4CXslp3Sy0z5Pg0Ov2u
# TEAu7PvqNtqUpO5tS6yjDFNy4ZP2c3iXbUWODwqTYjGCEXAwghFsAgEBMH0waTEL
# MAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhE
# aWdpQ2VydCBUcnVzdGVkIEc0IENvZGUgU2lnbmluZyBSU0E0MDk2IFNIQTM4NCAy
# MDIxIENBMQIQDlgwK3bdwYTsyouCrP/G5zANBglghkgBZQMEAgEFAKCBhDAYBgor
# BgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEE
# MBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBS
# pqHvo4Us92fvBPuSGFE9YFZWTrH9WvJrhaY6iGawOjANBgkqhkiG9w0BAQEFAASC
# AgBLgtOOxIWp+ynMiVd49ru4UaxXyD1acJ3rT3wT16d3qNXCtvnHX3pqVhS7LBhP
# qSPQHdCvB9I5doixG8OmKEpQSr+p2fgHLx5aS6PfWMl1iKurr/ci3JNW0t05QBQy
# 8zGTnS9GbM6DWuktzxhA8kH6VadZCH1Ko17w0M3O6/JgLBCPXu0bWT1AcJLL+Pd8
# rTxba+VeM2zviVUjYQMXywSEE7ZNcjkpBBWeIKUYga+/tYkT/LfjFIR48W2ip+Am
# D31FYJzS1by5FohlcjFgoEgV3ulltuV29nwD4EvZY66CzZh2Il9e8CoFYDXg/KDm
# za/DgdMKaVI/CwxHWOTntqiMK4DehAZuZeBIJPrYcLIeugARoJoa2vVNd0TFO0wN
# tdJn0qAwu3k0d2w+3vX+nb9GaNrEBhJj8rbUBkL57XkaVAQBl0KKjsXNlznH3n5M
# Kk0S2Zau2eAvAZinn9PANM+x7zeiWWEV124dmQ41mgOzbQByJizMckqVP7f/oCw8
# og0fccX5cF4kwC7J/0ba5ghsvlddnN5eAFd2PfOf012a+/f/2ydAxDWW5YGiT4f/
# 3eQLC+dtjRkmlZ8F9cQllgmkzFKNGDTywKd3It1w1nAci7UbC9bYUKDAddkGfEEn
# 6ccu72OjAkWdgGQRuLtvWD2Uh1U/ti5S52bJvMsZcFaZF6GCDj0wgg45BgorBgEE
# AYI3AwMBMYIOKTCCDiUGCSqGSIb3DQEHAqCCDhYwgg4SAgEDMQ0wCwYJYIZIAWUD
# BAIBMIIBDwYLKoZIhvcNAQkQAQSggf8EgfwwgfkCAQEGC2CGSAGG+EUBBxcDMDEw
# DQYJYIZIAWUDBAIBBQAEIMpxYi00ouSwlPb4V9X+2tKPvVmUbZc9i7Jt6wDlaxYH
# AhUAwua+p2NFbBZe1cFzxVhucrEkK04YDzIwMjMxMDE3MDYyMDUxWjADAgEeoIGG
# pIGDMIGAMQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRp
# b24xHzAdBgNVBAsTFlN5bWFudGVjIFRydXN0IE5ldHdvcmsxMTAvBgNVBAMTKFN5
# bWFudGVjIFNIQTI1NiBUaW1lU3RhbXBpbmcgU2lnbmVyIC0gRzOgggqLMIIFODCC
# BCCgAwIBAgIQewWx1EloUUT3yYnSnBmdEjANBgkqhkiG9w0BAQsFADCBvTELMAkG
# A1UEBhMCVVMxFzAVBgNVBAoTDlZlcmlTaWduLCBJbmMuMR8wHQYDVQQLExZWZXJp
# U2lnbiBUcnVzdCBOZXR3b3JrMTowOAYDVQQLEzEoYykgMjAwOCBWZXJpU2lnbiwg
# SW5jLiAtIEZvciBhdXRob3JpemVkIHVzZSBvbmx5MTgwNgYDVQQDEy9WZXJpU2ln
# biBVbml2ZXJzYWwgUm9vdCBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTAeFw0xNjAx
# MTIwMDAwMDBaFw0zMTAxMTEyMzU5NTlaMHcxCzAJBgNVBAYTAlVTMR0wGwYDVQQK
# ExRTeW1hbnRlYyBDb3Jwb3JhdGlvbjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1c3Qg
# TmV0d29yazEoMCYGA1UEAxMfU3ltYW50ZWMgU0hBMjU2IFRpbWVTdGFtcGluZyBD
# QTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALtZnVlVT52Mcl0agaLr
# VfOwAa08cawyjwVrhponADKXak3JZBRLKbvC2Sm5Luxjs+HPPwtWkPhiG37rpgfi
# 3n9ebUA41JEG50F8eRzLy60bv9iVkfPw7mz4rZY5Ln/BJ7h4OcWEpe3tr4eOzo3H
# berSmLU6Hx45ncP0mqj0hOHE0XxxxgYptD/kgw0mw3sIPk35CrczSf/KO9T1sptL
# 4YiZGvXA6TMU1t/HgNuR7v68kldyd/TNqMz+CfWTN76ViGrF3PSxS9TO6AmRX7WE
# eTWKeKwZMo8jwTJBG1kOqT6xzPnWK++32OTVHW0ROpL2k8mc40juu1MO1DaXhnjF
# oTcCAwEAAaOCAXcwggFzMA4GA1UdDwEB/wQEAwIBBjASBgNVHRMBAf8ECDAGAQH/
# AgEAMGYGA1UdIARfMF0wWwYLYIZIAYb4RQEHFwMwTDAjBggrBgEFBQcCARYXaHR0
# cHM6Ly9kLnN5bWNiLmNvbS9jcHMwJQYIKwYBBQUHAgIwGRoXaHR0cHM6Ly9kLnN5
# bWNiLmNvbS9ycGEwLgYIKwYBBQUHAQEEIjAgMB4GCCsGAQUFBzABhhJodHRwOi8v
# cy5zeW1jZC5jb20wNgYDVR0fBC8wLTAroCmgJ4YlaHR0cDovL3Muc3ltY2IuY29t
# L3VuaXZlcnNhbC1yb290LmNybDATBgNVHSUEDDAKBggrBgEFBQcDCDAoBgNVHREE
# ITAfpB0wGzEZMBcGA1UEAxMQVGltZVN0YW1wLTIwNDgtMzAdBgNVHQ4EFgQUr2PW
# yqNOhXLgp7xB8ymiOH+AdWIwHwYDVR0jBBgwFoAUtnf6aUhHn1MS1cLqBzJ2B9GX
# BxkwDQYJKoZIhvcNAQELBQADggEBAHXqsC3VNBlcMkX+DuHUT6Z4wW/X6t3cT/Oh
# yIGI96ePFeZAKa3mXfSi2VZkhHEwKt0eYRdmIFYGmBmNXXHy+Je8Cf0ckUfJ4uiN
# A/vMkC/WCmxOM+zWtJPITJBjSDlAIcTd1m6JmDy1mJfoqQa3CcmPU1dBkC/hHk1O
# 3MoQeGxCbvC2xfhhXFL1TvZrjfdKer7zzf0D19n2A6gP41P3CnXsxnUuqmaFBJm3
# +AZX4cYO9uiv2uybGB+queM6AL/OipTLAduexzi7D1Kr0eOUA2AKTaD+J20UMvw/
# l0Dhv5mJ2+Q5FL3a5NPD6itas5VYVQR9x5rsIwONhSrS/66pYYEwggVLMIIEM6AD
# AgECAhB71OWvuswHP6EBIwQiQU0SMA0GCSqGSIb3DQEBCwUAMHcxCzAJBgNVBAYT
# AlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3JhdGlvbjEfMB0GA1UECxMWU3lt
# YW50ZWMgVHJ1c3QgTmV0d29yazEoMCYGA1UEAxMfU3ltYW50ZWMgU0hBMjU2IFRp
# bWVTdGFtcGluZyBDQTAeFw0xNzEyMjMwMDAwMDBaFw0yOTAzMjIyMzU5NTlaMIGA
# MQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24xHzAd
# BgNVBAsTFlN5bWFudGVjIFRydXN0IE5ldHdvcmsxMTAvBgNVBAMTKFN5bWFudGVj
# IFNIQTI1NiBUaW1lU3RhbXBpbmcgU2lnbmVyIC0gRzMwggEiMA0GCSqGSIb3DQEB
# AQUAA4IBDwAwggEKAoIBAQCvDoqq+Ny/aXtUF3FHCb2NPIH4dBV3Z5Cc/d5OAp5L
# dvblNj5l1SQgbTD53R2D6T8nSjNObRaK5I1AjSKqvqcLG9IHtjy1GiQo+BtyUT3I
# CYgmCDr5+kMjdUdwDLNfW48IHXJIV2VNrwI8QPf03TI4kz/lLKbzWSPLgN4TTfkQ
# yaoKGGxVYVfR8QIsxLWr8mwj0p8NDxlsrYViaf1OhcGKUjGrW9jJdFLjV2wiv1V/
# b8oGqz9KtyJ2ZezsNvKWlYEmLP27mKoBONOvJUCbCVPwKVeFWF7qhUhBIYfl3rTT
# JrJ7QFNYeY5SMQZNlANFxM48A+y3API6IsW0b+XvsIqbAgMBAAGjggHHMIIBwzAM
# BgNVHRMBAf8EAjAAMGYGA1UdIARfMF0wWwYLYIZIAYb4RQEHFwMwTDAjBggrBgEF
# BQcCARYXaHR0cHM6Ly9kLnN5bWNiLmNvbS9jcHMwJQYIKwYBBQUHAgIwGRoXaHR0
# cHM6Ly9kLnN5bWNiLmNvbS9ycGEwQAYDVR0fBDkwNzA1oDOgMYYvaHR0cDovL3Rz
# LWNybC53cy5zeW1hbnRlYy5jb20vc2hhMjU2LXRzcy1jYS5jcmwwFgYDVR0lAQH/
# BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMHcGCCsGAQUFBwEBBGswaTAq
# BggrBgEFBQcwAYYeaHR0cDovL3RzLW9jc3Aud3Muc3ltYW50ZWMuY29tMDsGCCsG
# AQUFBzAChi9odHRwOi8vdHMtYWlhLndzLnN5bWFudGVjLmNvbS9zaGEyNTYtdHNz
# LWNhLmNlcjAoBgNVHREEITAfpB0wGzEZMBcGA1UEAxMQVGltZVN0YW1wLTIwNDgt
# NjAdBgNVHQ4EFgQUpRMBqZ+FzBtuFh5fOzGqeTYAex0wHwYDVR0jBBgwFoAUr2PW
# yqNOhXLgp7xB8ymiOH+AdWIwDQYJKoZIhvcNAQELBQADggEBAEaer/C4ol+imUjP
# qCdLIc2yuaZycGMv41UpezlGTud+ZQZYi7xXipINCNgQujYk+gp7+zvTYr9KlBXm
# gtuKVG3/KP5nz3E/5jMJ2aJZEPQeSv5lzN7Ua+NSKXUASiulzMub6KlN97QXWZJB
# w7c/hub2wH9EPEZcF1rjpDvVaSbVIX3hgGd+Yqy3Ti4VmuWcI69bEepxqUH5DXk4
# qaENz7Sx2j6aescixXTN30cJhsT8kSWyG5bphQjo3ep0YG5gpVZ6DchEWNzm+UgU
# nuW/3gC9d7GYFHIUJN/HESwfAD/DSxTGZxzMHgajkF9cVIs+4zNbgg/Ft4YCTnGf
# 6WZFP3YxggJaMIICVgIBATCBizB3MQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3lt
# YW50ZWMgQ29ycG9yYXRpb24xHzAdBgNVBAsTFlN5bWFudGVjIFRydXN0IE5ldHdv
# cmsxKDAmBgNVBAMTH1N5bWFudGVjIFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0ECEHvU
# 5a+6zAc/oQEjBCJBTRIwCwYJYIZIAWUDBAIBoIGkMBoGCSqGSIb3DQEJAzENBgsq
# hkiG9w0BCRABBDAcBgkqhkiG9w0BCQUxDxcNMjMxMDE3MDYyMDUxWjAvBgkqhkiG
# 9w0BCQQxIgQgJPRd0EFpzXUB6WW6cfxVk9J/rUW7YHW31TX9qsv8/zwwNwYLKoZI
# hvcNAQkQAi8xKDAmMCQwIgQgxHTOdgB9AjlODaXk3nwUxoD54oIBPP72U+9dtx/f
# YfgwCwYJKoZIhvcNAQEBBIIBAG3VKOBYjpS2Q47HmBsKfSpFpr4X6KnRQWmm1T+P
# 7ATSsoWImhW/VgWH4JTWqUtmNBSnOYEc6J2tUhqZ9tbfuK1V8ooQ7kt0J7XVXGlk
# BFiFvNrfG56btm3oD7Tt5CL5Bng5UlAaIkzjEpvkImPrZakC5TVPmsItCU03Os7A
# UriLzUYKZH/HJrftcvCJorftsm/G9zKk+gRJVXdFPjc0ZN1SXflvH87MJntx2ZlR
# q8cG5NVhfSkLjA0huIEf78RxBWVMnhQVT/e5GUZPFexUMems4sajHlds2qOFmuBw
# 2ZzCW88FcHIYBq7EdWP5U7mcd61Z2uEgztFY1irNU9wcNhI=
# SIG # End signature block

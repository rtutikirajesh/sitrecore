Import-Module "$PSScriptRoot\Sitecore.Cloud.Cmdlets.dll"

# public funcitons
Function Start-SitecoreAzureWFFMPackaging {
    <#
        .SYNOPSIS
        Using this command you can create Sitecore Azure WFFM Module web deploy packages

        .DESCRIPTION
        Creates valid Sitecore Azure WFFM Module web deploy packages for all SKU

        .PARAMETER WffmPath
        Path to the Sitecore's wffm module package zip file

        .PARAMETER ReportingWffmPath
        Path to the Sitecore's wffm reporting module package zip file

        .PARAMETER DestinationFolderPath
        Destination folder path which web deploy packages will be generated into

        .PARAMETER CargoPayloadFolderPath
        Path to the root folder containing cargo payloads (*.sccpl files)

        .PARAMETER ParameterXmlPath
        Path to the root folder containing MS Deploy xml files (parameters.xml)

        .EXAMPLE
        Start-WFFMAzurePackaging -WffmPath "D:\Sitecore\Modules\Web Forms for Marketers 8.2 rev. 161129.zip" -ReportingWffmPath "D:\Sitecore\Modules\Web Forms for Marketers Reporting 8.2 rev. 161129.zip" -DestinationFolderPath "D:\Work\WFFMPackaging\Wdps" -CargoPayloadFolderPath "D:\Project\Source\GitRepos\Cloud.Services.Provisioning.Data\Resources\WFFM 8.2.1\CargoPayloads" -ParameterXmlPath "D:\Project\Source\GitRepos\Cloud.Services.Provisioning.Data\Resources\WFFM 8.2.1\MsDeployXmls"
    #>

    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
		[string]$WffmPath,
        [parameter(Mandatory=$false)]
		[string]$ReportingWffmPath,
        [parameter(Mandatory=$true)]
        [string]$DestinationFolderPath,
        [parameter(Mandatory=$true)]
        [string]$CargoPayloadFolderPath,
        [parameter(Mandatory=$true)]
        [string]$ParameterXmlPath
    )

    try {
        $cdCargoPayloadPath = "$CargoPayloadFolderPath\WFFM.Cloud.RoleSpecific_CD.sccpl"
        $prcCargoPayloadPath = "$CargoPayloadFolderPath\WFFM.Cloud.RoleSpecific_PRC.sccpl"
        $xdbSingleCargoPayloadPath = "$CargoPayloadFolderPath\WFFM.Cloud.Role_Specific_XDBSingle.sccpl"
        $repCargoPayloadPath = ""
        $captchaHandlersEmbedCargoPayloadPath = "$CargoPayloadFolderPath\WFFM.Cloud.Embed.CaptchaHandlers.sccpl"
        $singleEmbedCargoPayloadPath = "$CargoPayloadFolderPath\WFFM.Cloud.Embed.RoleSpecific_Single.sccpl"
        $cdEmbedCargoPayloadPath="$CargoPayloadFolderPath\WFFM.Cloud.Embed.RoleSpecific_CD.sccpl"
        $cmEmbedCargoPayloadPath="$CargoPayloadFolderPath\WFFM.Cloud.Embed.RoleSpecific_CM.sccpl"
        $cdWdpParametersXml = "$ParameterXmlPath\CD\parameters.xml"
        $prcWdpParametersXml = "$ParameterXmlPath\PRC\parameters.xml"
        $singleWdpParametersXml = "$ParameterXmlPath\Single\parameters.xml"
        $xdbSingleWdpParametersXml = "$ParameterXmlPath\XDBSingle\parameters.xml"

        if (!$ReportingWffmPath) {
            $ReportingWffmPath = $WffmPath
            $repCargoPayloadPath = "$CargoPayloadFolderPath\WFFM.Cloud.RoleSpecific_REP.sccpl"
            $singleEmbedCargoPayloadPath = $captchaHandlersEmbedCargoPayloadPath
            $cdEmbedCargoPayloadPath = $captchaHandlersEmbedCargoPayloadPath
            $cmEmbedCargoPayloadPath = $captchaHandlersEmbedCargoPayloadPath
            #XDBSingle
            $xdbSingleDestFolder = "$DestinationFolderPath\XDBSingle"
            CreateXDBSingleWffmWdps $xdbSingleDestFolder $WffmPath $xdbSingleWdpParametersXml $xdbSingleCargoPayloadPath
        }

        #XPSingle
        $xpSingleDestFolder = "$DestinationFolderPath\XPSingle"
        CreateSingleWffmWdps $xpSingleDestFolder  $WffmPath $singleEmbedCargoPayloadPath $singleWdpParametersXml

        #XP
        $xpDestFolder = "$DestinationFolderPath\XP"
        CreateCmWffmWdps $xpDestFolder $WffmPath $cmEmbedCargoPayloadPath
        CreateCdWffmWdps $xpDestFolder $WffmPath $cdCargoPayloadPath $cdEmbedCargoPayloadPath $cdWdpParametersXml
        CreatePrcWffmWdps $xpDestFolder $WffmPath $prcCargoPayloadPath $prcWdpParametersXml
        CreateRepWffmWdps $xpDestFolder $ReportingWffmPath $repCargoPayloadPath

        #XDB
        $xdbDestFolder = "$DestinationFolderPath\XDB"
        CreatePrcWffmWdps $xdbDestFolder $WffmPath $prcCargoPayloadPath $prcWdpParametersXml
        CreateRepWffmWdps $xdbDestFolder $ReportingWffmPath $repCargoPayloadPath
    }
    catch {
        Write-Host $_.Exception.Message
        Break
    }
}

# Export public functions
Export-ModuleMember -Function Start-SitecoreAzureWFFMPackaging

Function CreateCmWffmWdps  {
    param(
        [string]$DestFolder,
        [string]$PackageSource,
        [string]$EmbedCargoPayload
        )

        #Create the Wffm Wdp
        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $PackageSource -Destination $DestFolder
        Update-SCWebDeployPackage -Path $wdpPath -EmbedCargoPayloadPath $EmbedCargoPayload

        #Rename the wdps to be CM specific
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_cm.scwdp.zip")
}

Function CreateCdWffmWdps {
    param(
        [string]$DestFolder,
        [string]$PackageSource,
        [string]$CargoPayload,
        [string]$EmbedCargoPayload,
        [string]$WdpParametersXml
        )

        #Create the Wffm Wdp
        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $PackageSource -Destination $DestFolder -Exclude "*.sql","*App_Data\poststeps\*"
        Update-SCWebDeployPackage -Path $wdpPath -EmbedCargoPayloadPath $EmbedCargoPayload
        Update-SCWebDeployPackage -Path $wdpPath -CargoPayloadPath $CargoPayload

        #Update the archive/parameters xmls
        Update-SCWebDeployPackage -Path $wdpPath -ParametersXmlPath $WdpParametersXml

        #Rename the wdps to be CD specific
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_cd.scwdp.zip")
}

Function CreatePrcWffmWdps {
    param(
        [string]$DestFolder,
        [string]$PackageSource,
        [string]$CargoPayload,
        [string]$WdpParametersXml
        )

        #Create the Wffm Wdp
        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $PackageSource -Destination $DestFolder -Exclude "core.sql","master.sql","*App_Data\poststeps\*"
        Update-SCWebDeployPackage -Path $wdpPath -CargoPayloadPath $CargoPayload

        #Update the archive/parameters xmls
        Update-SCWebDeployPackage -Path $wdpPath -ParametersXmlPath $WdpParametersXml

        #Rename the wdps to be PRC specific
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_prc.scwdp.zip")
}

Function CreateRepWffmWdps {
    param(
        [string]$DestFolder,
        [string]$PackageSource,
        [string]$CargoPayload
        )

        #Create the Wffm Wdp
        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $PackageSource -Destination $DestFolder -Exclude "core.sql","master.sql","*App_Data\poststeps\*"

        if ($CargoPayload) {
            Update-SCWebDeployPackage -Path $wdpPath -CargoPayloadPath $CargoPayload
        }

        #Rename the wdps to be REP specific
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_rep.scwdp.zip")
}

Function CreateSingleWffmWdps {
    param(
        [string]$DestFolder,
        [string]$PackageSource,
        [string]$EmbedCargoPayload,
        [string]$ParametersXml
        )

        #Create the Wffm Wdp

        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $PackageSource -Destination $DestFolder

        Update-SCWebDeployPackage -Path $wdpPath -EmbedCargoPayloadPath $EmbedCargoPayload

        #Update the archive/parameters xmls
        Update-SCWebDeployPackage -Path $wdpPath -ParametersXmlPath $ParametersXml

        #Rename the wdps to be Single specific
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_single.scwdp.zip")
}

Function CreateXDBSingleWffmWdps {
    param(
        [string]$DestFolder,
        [string]$PackageSource,
        [string]$ParametersXml,
        [string]$CargoPayload
        )

        #Create the Wffm Wdp
        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $PackageSource -Destination $DestFolder -Exclude "core.sql","master.sql","*App_Data\poststeps\*"
        Update-SCWebDeployPackage -Path $wdpPath -CargoPayloadPath $CargoPayload

        #Update the archive/parameters xmls
        Update-SCWebDeployPackage -Path $wdpPath -ParametersXmlPath $ParametersXml

        #Rename the wdps to be XDBSingle specific
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_xdbsingle.scwdp.zip")
}
# SIG # Begin signature block
# MIImLgYJKoZIhvcNAQcCoIImHzCCJhsCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD5eUCuHqY+dgYn
# dV8WTmzNMX90lPsPECKhReMIox1jYqCCFBUwggWQMIIDeKADAgECAhAFmxtXno4h
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
# TEAu7PvqNtqUpO5tS6yjDFNy4ZP2c3iXbUWODwqTYjGCEW8wghFrAgEBMH0waTEL
# MAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhE
# aWdpQ2VydCBUcnVzdGVkIEc0IENvZGUgU2lnbmluZyBSU0E0MDk2IFNIQTM4NCAy
# MDIxIENBMQIQDlgwK3bdwYTsyouCrP/G5zANBglghkgBZQMEAgEFAKCBhDAYBgor
# BgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEE
# MBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEiBCD+
# 876+OdSJINRmu5L6LoHXKsVij8icpi6w+ne9SlxymzANBgkqhkiG9w0BAQEFAASC
# AgAluT4q5l1qElIJowbVdyiPnMN51p16JYYzARY4m17AGr3TN4VG0Iej72R9mxMt
# JTr4lDeuNMFKfmpmYIJp4chpmF20vndiXk4Q0kOzDwvrhmcZQPx6YTBNlPIkhZP/
# RvKFP3hXewE/gbbNQbrMI8QbLfK0iqEcULoBoLu20o44B1+UY0pwAsuz/WknypKo
# QVJc8z6m2+sli5D75N5z6L42lDucNihjdNUjMIk0pAeFTrBOof3EkBp6p1Biysi3
# aHM0xERcRE9BylsqqYohnOMhqjB96DXLcTypERskeY/rU9HlhKsMR3RbfV2qzmhv
# MkCtlWyi3+EtxidWHzTn/aqWlenFFG1SyBYr+R7U0fuAoj401JApGxj1f9jVhXX4
# s7i2c7Cia6dGbwulcYautYj2DeEAm8vDiBMz2iVV/9MCI4FLO8vzC7SpqTw6TBXN
# QVfelLxbI2mYYwHK6T1mJHNTvaEVlvKH8xNjhxvgKDWm/auvK7SS4tm9VfDZIgBz
# 2meREddFNGxiESqNLdSFz62CNNBhAB+7WGpwGX8+XgJ+/Jv446Y+zwdiAzbwubSr
# TQdzx1alSitWbrn/L7XyntrDoZF5GGd+FiNdLI2W+jpLXVYtRrKEw6kswgDo88zv
# 2nA6C9x+gBPSAahBXDJMDWhuxIJZWv9a4ylC2UYvytI1S6GCDjwwgg44BgorBgEE
# AYI3AwMBMYIOKDCCDiQGCSqGSIb3DQEHAqCCDhUwgg4RAgEDMQ0wCwYJYIZIAWUD
# BAIBMIIBDgYLKoZIhvcNAQkQAQSggf4EgfswgfgCAQEGC2CGSAGG+EUBBxcDMDEw
# DQYJYIZIAWUDBAIBBQAEIIarFkXravnyrFOioqrfHjDzFCKDfBv9IMxzHo6oVm+U
# AhRRjA4VNVgBfJW6/dxaBtZGPevjVhgPMjAyMzEwMTcwNjIwNTRaMAMCAR6ggYak
# gYMwgYAxCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3JhdGlv
# bjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29yazExMC8GA1UEAxMoU3lt
# YW50ZWMgU0hBMjU2IFRpbWVTdGFtcGluZyBTaWduZXIgLSBHM6CCCoswggU4MIIE
# IKADAgECAhB7BbHUSWhRRPfJidKcGZ0SMA0GCSqGSIb3DQEBCwUAMIG9MQswCQYD
# VQQGEwJVUzEXMBUGA1UEChMOVmVyaVNpZ24sIEluYy4xHzAdBgNVBAsTFlZlcmlT
# aWduIFRydXN0IE5ldHdvcmsxOjA4BgNVBAsTMShjKSAyMDA4IFZlcmlTaWduLCBJ
# bmMuIC0gRm9yIGF1dGhvcml6ZWQgdXNlIG9ubHkxODA2BgNVBAMTL1ZlcmlTaWdu
# IFVuaXZlcnNhbCBSb290IENlcnRpZmljYXRpb24gQXV0aG9yaXR5MB4XDTE2MDEx
# MjAwMDAwMFoXDTMxMDExMTIzNTk1OVowdzELMAkGA1UEBhMCVVMxHTAbBgNVBAoT
# FFN5bWFudGVjIENvcnBvcmF0aW9uMR8wHQYDVQQLExZTeW1hbnRlYyBUcnVzdCBO
# ZXR3b3JrMSgwJgYDVQQDEx9TeW1hbnRlYyBTSEEyNTYgVGltZVN0YW1waW5nIENB
# MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAu1mdWVVPnYxyXRqBoutV
# 87ABrTxxrDKPBWuGmicAMpdqTclkFEspu8LZKbku7GOz4c8/C1aQ+GIbfuumB+Le
# f15tQDjUkQbnQXx5HMvLrRu/2JWR8/DubPitljkuf8EnuHg5xYSl7e2vh47Ojcdt
# 6tKYtTofHjmdw/SaqPSE4cTRfHHGBim0P+SDDSbDewg+TfkKtzNJ/8o71PWym0vh
# iJka9cDpMxTW38eA25Hu/rySV3J39M2ozP4J9ZM3vpWIasXc9LFL1M7oCZFftYR5
# NYp4rBkyjyPBMkEbWQ6pPrHM+dYr77fY5NUdbRE6kvaTyZzjSO67Uw7UNpeGeMWh
# NwIDAQABo4IBdzCCAXMwDgYDVR0PAQH/BAQDAgEGMBIGA1UdEwEB/wQIMAYBAf8C
# AQAwZgYDVR0gBF8wXTBbBgtghkgBhvhFAQcXAzBMMCMGCCsGAQUFBwIBFhdodHRw
# czovL2Quc3ltY2IuY29tL2NwczAlBggrBgEFBQcCAjAZGhdodHRwczovL2Quc3lt
# Y2IuY29tL3JwYTAuBggrBgEFBQcBAQQiMCAwHgYIKwYBBQUHMAGGEmh0dHA6Ly9z
# LnN5bWNkLmNvbTA2BgNVHR8ELzAtMCugKaAnhiVodHRwOi8vcy5zeW1jYi5jb20v
# dW5pdmVyc2FsLXJvb3QuY3JsMBMGA1UdJQQMMAoGCCsGAQUFBwMIMCgGA1UdEQQh
# MB+kHTAbMRkwFwYDVQQDExBUaW1lU3RhbXAtMjA0OC0zMB0GA1UdDgQWBBSvY9bK
# o06FcuCnvEHzKaI4f4B1YjAfBgNVHSMEGDAWgBS2d/ppSEefUxLVwuoHMnYH0ZcH
# GTANBgkqhkiG9w0BAQsFAAOCAQEAdeqwLdU0GVwyRf4O4dRPpnjBb9fq3dxP86HI
# gYj3p48V5kApreZd9KLZVmSEcTAq3R5hF2YgVgaYGY1dcfL4l7wJ/RyRR8ni6I0D
# +8yQL9YKbE4z7Na0k8hMkGNIOUAhxN3WbomYPLWYl+ipBrcJyY9TV0GQL+EeTU7c
# yhB4bEJu8LbF+GFcUvVO9muN90p6vvPN/QPX2fYDqA/jU/cKdezGdS6qZoUEmbf4
# Blfhxg726K/a7JsYH6q54zoAv86KlMsB257HOLsPUqvR45QDYApNoP4nbRQy/D+X
# QOG/mYnb5DkUvdrk08PqK1qzlVhVBH3HmuwjA42FKtL/rqlhgTCCBUswggQzoAMC
# AQICEHvU5a+6zAc/oQEjBCJBTRIwDQYJKoZIhvcNAQELBQAwdzELMAkGA1UEBhMC
# VVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMR8wHQYDVQQLExZTeW1h
# bnRlYyBUcnVzdCBOZXR3b3JrMSgwJgYDVQQDEx9TeW1hbnRlYyBTSEEyNTYgVGlt
# ZVN0YW1waW5nIENBMB4XDTE3MTIyMzAwMDAwMFoXDTI5MDMyMjIzNTk1OVowgYAx
# CzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3JhdGlvbjEfMB0G
# A1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29yazExMC8GA1UEAxMoU3ltYW50ZWMg
# U0hBMjU2IFRpbWVTdGFtcGluZyBTaWduZXIgLSBHMzCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAK8Oiqr43L9pe1QXcUcJvY08gfh0FXdnkJz93k4Cnkt2
# 9uU2PmXVJCBtMPndHYPpPydKM05tForkjUCNIqq+pwsb0ge2PLUaJCj4G3JRPcgJ
# iCYIOvn6QyN1R3AMs19bjwgdckhXZU2vAjxA9/TdMjiTP+UspvNZI8uA3hNN+RDJ
# qgoYbFVhV9HxAizEtavybCPSnw0PGWythWJp/U6FwYpSMatb2Ml0UuNXbCK/VX9v
# ygarP0q3InZl7Ow28paVgSYs/buYqgE4068lQJsJU/ApV4VYXuqFSEEhh+XetNMm
# sntAU1h5jlIxBk2UA0XEzjwD7LcA8joixbRv5e+wipsCAwEAAaOCAccwggHDMAwG
# A1UdEwEB/wQCMAAwZgYDVR0gBF8wXTBbBgtghkgBhvhFAQcXAzBMMCMGCCsGAQUF
# BwIBFhdodHRwczovL2Quc3ltY2IuY29tL2NwczAlBggrBgEFBQcCAjAZGhdodHRw
# czovL2Quc3ltY2IuY29tL3JwYTBABgNVHR8EOTA3MDWgM6Axhi9odHRwOi8vdHMt
# Y3JsLndzLnN5bWFudGVjLmNvbS9zaGEyNTYtdHNzLWNhLmNybDAWBgNVHSUBAf8E
# DDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwdwYIKwYBBQUHAQEEazBpMCoG
# CCsGAQUFBzABhh5odHRwOi8vdHMtb2NzcC53cy5zeW1hbnRlYy5jb20wOwYIKwYB
# BQUHMAKGL2h0dHA6Ly90cy1haWEud3Muc3ltYW50ZWMuY29tL3NoYTI1Ni10c3Mt
# Y2EuY2VyMCgGA1UdEQQhMB+kHTAbMRkwFwYDVQQDExBUaW1lU3RhbXAtMjA0OC02
# MB0GA1UdDgQWBBSlEwGpn4XMG24WHl87Map5NgB7HTAfBgNVHSMEGDAWgBSvY9bK
# o06FcuCnvEHzKaI4f4B1YjANBgkqhkiG9w0BAQsFAAOCAQEARp6v8LiiX6KZSM+o
# J0shzbK5pnJwYy/jVSl7OUZO535lBliLvFeKkg0I2BC6NiT6Cnv7O9Niv0qUFeaC
# 24pUbf8o/mfPcT/mMwnZolkQ9B5K/mXM3tRr41IpdQBKK6XMy5voqU33tBdZkkHD
# tz+G5vbAf0Q8RlwXWuOkO9VpJtUhfeGAZ35irLdOLhWa5Zwjr1sR6nGpQfkNeTip
# oQ3PtLHaPpp6xyLFdM3fRwmGxPyRJbIblumFCOjd6nRgbmClVnoNyERY3Ob5SBSe
# 5b/eAL13sZgUchQk38cRLB8AP8NLFMZnHMweBqOQX1xUiz7jM1uCD8W3hgJOcZ/p
# ZkU/djGCAlowggJWAgEBMIGLMHcxCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1h
# bnRlYyBDb3Jwb3JhdGlvbjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29y
# azEoMCYGA1UEAxMfU3ltYW50ZWMgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQe9Tl
# r7rMBz+hASMEIkFNEjALBglghkgBZQMEAgGggaQwGgYJKoZIhvcNAQkDMQ0GCyqG
# SIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEPFw0yMzEwMTcwNjIwNTRaMC8GCSqGSIb3
# DQEJBDEiBCBonFYgzZ4uUOODvBAnZ1+qjr94tN/mJkkUvEPPqxvsjTA3BgsqhkiG
# 9w0BCRACLzEoMCYwJDAiBCDEdM52AH0COU4NpeTefBTGgPniggE8/vZT7123H99h
# +DALBgkqhkiG9w0BAQEEggEAEcPkZmo7maP3E2gOeXmuZINbcLjJYvCv8fcRYxZY
# GWf0eQzwnjedNiH3kqKluV8+3HmZhDkxI5esHLEw/0o0UIUnDanQU2abf8hiDGSN
# 1ifoY2QFpCQm0XI+45kv9XWTafpmY+6tal4BydPTiICA757SOmkhbzJi8wrLnNE5
# J7VZSWNXMxEs7Mda79OCpDidrP23iWIMB/jGmgS1HxfU39HlwnRgU7HaoGUFh0X8
# R37DR0R4V7onT3eLu7tbAbWqGmhtj6aSysaGo1DWPWlUUsEzLsEx54CO5WeeTEEp
# h85P1qNvFPnoQpQIbcZRNbzIki0JejDkij6+S1KE8OOCEw==
# SIG # End signature block

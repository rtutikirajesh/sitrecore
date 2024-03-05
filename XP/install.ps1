$SCSDK="/home/rajeshtutiki/sitrecore/XP/Sitecore Azure Toolkit 3.0.0-r02547.1547"
$SCTemplates="https://github.com/rtutikirajesh/sitrecore/tree/main/XP"
$DeploymentId = "sitecore-xp-scaled"
$LicenseFile = "/home/rajeshtutiki/sitrecore/XP/license.xml"
$SubscriptionId = "42c342a3-b2db-4152-8914-f87ba358e0ff"
$Location="East US"
$ParamFile="/home/rajeshtutiki/sitrecore/XP/azuredeploy.parameters.json"
$Parameters = @{
     #set the size of all recommended instance sizes   
     "sitecoreSKU"="Medium";
     #by default this installs azuresearch
     #if you uncomment the following it will use an existing solr connectionstring that
     # you have created instead of using AzureSearch
     #"solrConnectionString"= "https://myinstancesomewhere/solr";
}
Import-Module $SCSDK\tools\Sitecore.Cloud.Cmdlets.psm1
 Import-Module Az.Accounts
       Connect-AzAccount
       Set-AzContext -SubscriptionId $SubscriptionId
Start-SitecoreAzureDeployment -Name $DeploymentId -Location $Location -ArmTemplateUrl "$SCTemplates/azuredeploy.json"  -ArmParametersPath $ParamFile  -LicenseXmlPath $LicenseFile  
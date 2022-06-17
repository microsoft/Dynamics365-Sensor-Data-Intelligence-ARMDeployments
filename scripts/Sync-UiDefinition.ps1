<#
.SYNOPSIS
    Partially automates population- and asserts correctness of the
    createUiDefinition.json file.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$azureDeployJson = Get-Content -Path "$PSScriptRoot/../azuredeploy.json" -Raw
$azureDeploy = $azureDeployJson | ConvertFrom-Json

$createUiDefinitionPath = "$PSScriptRoot/../createUiDefinition.json"
$createUiDefinition = Get-Content -Raw -Path $createUiDefinitionPath | ConvertFrom-Json
$enabledScenarios = $createUiDefinition.parameters.basics[0].elements | Where-Object { $_.name -eq 'enabledScenarios' }

$enabledScenariosAllowedValues = $()

foreach ($asaJobConfigPath in (Get-ChildItem -Path "$PSScriptRoot/../stream-analytics-queries/*/JobConfig.json")) {
    $asaJobConfig = Get-Content -Raw -Path $asaJobConfigPath | ConvertFrom-Json

    $metadata = $asaJobConfig.SDIMetadata

    if (-not $metadata) {
        throw "Missing SDIMetadata property from job config: $asaJobConfigPath. Look at other ``JobConfig.json`` files for reference."
    }

    $parameterName = "start$($metadata.id)Job"
    $parameter = $azureDeploy.parameters.$parameterName

    if ((-not $parameter) -or $parameter.type -ne 'bool') {
        throw "Missing enablement bool Bicep parameter: `"$parameterName`""
    }

    $enabledScenariosAllowedValues += @([ordered]@{
        label       = $metadata.label
        description = $metadata.description
        value       = $metadata.id
    })
}

$enabledScenarios.constraints.allowedValues = $enabledScenariosAllowedValues
$createUiDefinitionJson = (Set-LineEndings -Value ($createUiDefinition | ConvertTo-Json -Depth 100)) + "`n"

Set-Content -Path $createUiDefinitionPath -Encoding utf8 -Value $createUiDefinitionJson -NoNewline

<#
.SYNOPSIS
    Builds a Bicep file to ARM, following best practices presented in:
    https://github.com/Azure/azure-quickstart-templates/blob/master/1-CONTRIBUTION-GUIDE/README.md.

.PARAMETER CopyOutputToClipboard
    Copy the ARM JSON output to the clipboard.
#>

# PowerShell 5's `ConvertTo-Json` has suboptimal JSON formatting
# and will cause diffs just on whitespace with other contributors
# to the repository, so we enforce V7 or higher.
#Requires -Version 7.0

param (
    [switch] $CopyOutputToClipboard
)

$ErrorActionPreference = 'Stop'

# Clear parameters from Logic App definitions (to avoid leaking private data to commits)
foreach ($logicAppPath in (Get-ChildItem -Path "$PSScriptRoot/../logic-apps/*.json")) {
    $logicAppDefinition = Get-Content -Raw -Path $logicAppPath | ConvertFrom-Json
    $logicAppDefinition.parameters = @{} # the entire object is ignored and can be omitted safely
    $logicAppDefinition.definition.parameters.PSObject.Properties | Where-Object { $_.Value.type -eq 'Object' } | ForEach-Object { $_.Value.defaultValue = @{} }
    $logicAppDefinition.definition.parameters.PSObject.Properties | Where-Object { $_.Value.type -eq 'String' } | ForEach-Object { $_.Value.defaultValue = '' }

    Set-Content -Path $logicAppPath -Encoding utf8 -Value ($logicAppDefinition | ConvertTo-Json -Depth 100)
}

az bicep build `
    --file $PSScriptRoot\..\main.bicep `
    --outfile $PSScriptRoot\..\azuredeploy.json

if ($CopyOutputToClipboard) {
    Get-Content `
        -Path $PSScriptRoot\..\azuredeploy.json `
        -Encoding utf8 `
        -Raw `
    | Set-Clipboard
}

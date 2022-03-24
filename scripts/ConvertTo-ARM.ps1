<#
.SYNOPSIS
    Converts a Bicep file to ARM, following best practices
    presented in:
    https://github.com/Azure/azure-quickstart-templates/blob/master/1-CONTRIBUTION-GUIDE/README.md.

.PARAMETER CopyOutputToClipboard
    Copy the ARM JSON output to the clipboard.
#>
param (
    [switch] $CopyOutputToClipboard
)

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

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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-LineEndings($Value) {
    return $Value.Replace("`r`n", "`n")
}

function Set-FileLineEndings($Path) {
    foreach ($itemPath in (Get-ChildItem -Recurse -Path $Path)) {
        $content = Get-Content -Raw -Path $itemPath

        $contentNewlinesSanitized = Set-LineEndings -Value $content

        Set-Content $itemPath -Encoding utf8 -Value $contentNewlinesSanitized -NoNewline
    }
}

# Clear parameters from Logic App definitions (to avoid leaking private data to commits)
foreach ($logicAppPath in (Get-ChildItem -Path "$PSScriptRoot/../logic-apps/*.json")) {
    $logicAppDefinition = Get-Content -Raw -Path $logicAppPath | ConvertFrom-Json
    $logicAppDefinition.parameters = @{} # the entire object is ignored and can be omitted safely
    $logicAppDefinition.definition.parameters.PSObject.Properties | Where-Object { $_.Value.type -eq 'Object' } | ForEach-Object { $_.Value.defaultValue = @{} }
    $logicAppDefinition.definition.parameters.PSObject.Properties | Where-Object { $_.Value.type -eq 'String' } | ForEach-Object { $_.Value.defaultValue = '' }

    # adding "`n" at end of JSON and using "-NoNewline" to avoid CRLF from creeping in on Windows machines
    $logicAppDefinitionJson = (Set-LineEndings -Value ($logicAppDefinition | ConvertTo-Json -Depth 100)) + "`n"

    Set-Content -Path $logicAppPath -Encoding utf8 -Value $logicAppDefinitionJson -NoNewline
}

# Replace CRLF with LF in query files to ensure Bicep compilation is platform-agnostic
Set-FileLineEndings -Path "$PSScriptRoot/../stream-analytics-queries/*.asaql"

az bicep build `
    --file "$PSScriptRoot/../main.bicep" `
    --outfile "$PSScriptRoot/../azuredeploy.json"

# Normalize line endings to be LF instead of CRLF
Set-FileLineEndings -Path "$PSScriptRoot/../azuredeploy.json"

& "$PSScriptRoot/Sync-UiDefinition.ps1"

if ($CopyOutputToClipboard) {
    Get-Content `
        -Path "$PSScriptRoot/../azuredeploy.json" `
        -Encoding utf8 `
        -Raw `
    | Set-Clipboard
}

Write-Host "Build completed successfully"

Set-StrictMode -Version Latest

function Assert-CIGeneratedTemplateHash($Template) {
    if (-not $env:GITHUB_ACTIONS) {
        # not running in CI workflow
        return
    }

    $ciTemplate = Get-Content "$PSScriptRoot/../_ci_generated_azuredeploy.json" | ConvertFrom-Json

    $committedHash = $Template.metadata._generator.templateHash
    $ciHash = $ciTemplate.metadata._generator.templateHash

    $committedUsingVersion = $Template.metadata._generator.version
    $ciUsingVersion = $ciTemplate.metadata._generator.version

    if ($committedHash -ne $ciHash) {
        Write-Error ("Current committed template hash ($committedHash) and hash of the CI-built template hash ($ciHash) are not the same.`n`n" `
            + "Potential reasons:`n" `
            + "* Your local Bicep version ($committedUsingVersion) and the one used by the CI container ($ciUsingVersion) are different.`n" `
            + "* You forgot to run ./scripts/Build-ARMTemplate.ps1 before committing your changes.")

        exit 1
    }

    Write-Host 'Template hashes validated.'
}

function Assert-TemplateUIParameters($Template, $UiDefinition) {
    $templateParameters = $Template.parameters.PSObject.Properties.name
    $uiOutputProperties = $UiDefinition.parameters.outputs.PSObject.Properties.name

    $difference = Compare-Object -ReferenceObject $templateParameters -DifferenceObject $uiOutputProperties

    if ([bool]$difference) {
        Format-Table -InputObject $difference

        Write-Error ("There is a difference between parameters declared in ARM template azuredeploy.json and parameters provided`n" `
            + "by createUiDefinition.json. See the difference above this error.")

        exit 1
    }

    Write-Host 'Template UI parameters validated.'
}

$template = Get-Content "$PSScriptRoot/../azuredeploy.json" | ConvertFrom-Json
$uiDefinition = Get-Content "$PSScriptRoot/../createUiDefinition.json" | ConvertFrom-Json

Assert-CIGeneratedTemplateHash -Template $template

Assert-TemplateUIParameters -Template $template -UiDefinition $uiDefinition

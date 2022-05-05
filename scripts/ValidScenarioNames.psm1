using namespace System.Management.Automation

<#
.SYNOPSIS
    Provides scenario names to usage of `ValidateSet`.
#>
class ValidScenarioNamesGenerator : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        $Values = (Get-ChildItem -Path "$PSScriptRoot/../stream-analytics-queries" -Directory).Name
        return $Values
    }
}

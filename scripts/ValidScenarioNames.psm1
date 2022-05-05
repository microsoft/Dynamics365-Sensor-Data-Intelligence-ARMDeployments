using namespace System.Management.Automation

class ValidScenarioNamesGenerator : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        $Values = (Get-ChildItem -Path "$PSScriptRoot/../stream-analytics-queries" -Directory).Name
        return $Values
    }
}

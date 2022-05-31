<#
.SYNOPSIS
    Generate Stream Analytics test config files.

.PARAMETER Scenario
    Scenario name to generate test config for.
    If not set, the script will generate test configs for all tests found in the repository.
#>

#Requires -Version 7.0

param(
    [ValidateSet(
        # add to this as and when new scenarios are created
        'asset-maintenance',
        'machine-reporting-status',
        'product-quality-validation'
    )]
    $Scenario
)

function New-StreamAnalyticsTestConfig($Scenario) {
    $ScenarioDirectory = "$PSScriptRoot/../stream-analytics-queries/$Scenario"
    $TestConfigPath = "$ScenarioDirectory/Test/testConfig.json"
    $ProjectPath = "$ScenarioDirectory/asaproj.json"
    If (Test-Path $TestConfigPath) {
        rm $TestConfigPath
    }
    $TestConfig = [ordered] @{
        Script = "../$Scenario.asaql"
        TestCases = @()
    }

    foreach ($TestCase in (Get-ChildItem -Path "$ScenarioDirectory/Test/*"  -Directory)) {
        $TestName = $TestCase.Name
        $CurrentTestCase = [ordered] @{
            Name = $TestName
            Inputs = @()
            ExpectedOutputs = @()
        }
        ForEach ($Input in (Get-ChildItem -Path "$ScenarioDirectory/Inputs/*.json")) {
            $InputConfig = Get-Content -Raw -Path $Input | ConvertFrom-Json
            $InputAlias = $InputConfig.InputAlias
            $CurrentTestCase.Inputs += [ordered] @{
                InputAlias = $InputAlias
                Type = $InputConfig.Type
                Format = "Json"
                FilePath = "$TestName/$InputAlias.json"
                ScriptType = "InputMock"
            }
        }

        $CurrentTestCase.ExpectedOutputs += [ordered] @{
            OutputAlias = "MetricOutput"
            FilePath = "$TestName/ExpectedMetricOutput.json"
            Required = Test-Path "$TestCase/ExpectedMetricOutput.json"
        }

        $CurrentTestCase.ExpectedOutputs += [ordered] @{
            OutputAlias = "NotificationOutput"
            FilePath = "$TestName/ExpectedNotificationOutput.json"
            Required = Test-Path "$TestCase/ExpectedNotificationOutput.json"
        }

        $TestConfig.TestCases += $CurrentTestCase
    }

    $TestConfigJson = ($TestConfig | ConvertTo-Json -Depth 100).Replace("`r`n", "`n")
    Set-Content -Path $TestConfigPath -Encoding utf8 -Value $TestConfigJson
}

if ($Scenario) {
    New-StreamAnalyticsTestConfig -Scenario $Scenario
}
else {
    foreach ($ScenarioPath in (Get-ChildItem -Path "$PSScriptRoot/../stream-analytics-queries/*" -Directory)) {
        $Scenario = $ScenarioPath.Name
        New-StreamAnalyticsTestConfig -Scenario $Scenario
    }
}

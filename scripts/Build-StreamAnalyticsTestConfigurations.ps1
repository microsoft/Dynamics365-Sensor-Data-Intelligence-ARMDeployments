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
        'asset-downtime',
        'asset-maintenance',
        'machine-reporting-status',
        'product-quality-validation',
        'production-job-delayed'
    )]
    $Scenario
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-StreamAnalyticsTestConfig($Scenario) {
    $scenarioDirectory = "$PSScriptRoot/../stream-analytics-queries/$Scenario"
    $testConfigPath = "$scenarioDirectory/Test/testConfig.json"

    If (Test-Path $testConfigPath) {
        Remove-Item -Path $testConfigPath
    }
    $testConfig = [ordered] @{
        Script    = "../$Scenario.asaql"
        TestCases = @()
    }

    foreach ($testCase in (Get-ChildItem -Path "$scenarioDirectory/Test/*" -Directory)) {
        $testName = $testCase.Name
        $currentTestCase = [ordered] @{
            Name            = $testName
            Inputs          = @()
            ExpectedOutputs = @()
        }
        ForEach ($Input in (Get-ChildItem -Path "$scenarioDirectory/Inputs/*.json")) {
            $inputConfig = Get-Content -Raw -Path $Input | ConvertFrom-Json
            $inputAlias = $inputConfig.InputAlias
            $currentTestCase.Inputs += [ordered]@{
                InputAlias = $inputAlias
                Type       = $inputConfig.Type
                Format     = "Json"
                FilePath   = "$testName/$inputAlias.json"
                ScriptType = "InputMock"
            }
        }

        $currentTestCase.ExpectedOutputs += [ordered] @{
            OutputAlias = "MetricOutput"
            FilePath    = "$testName/ExpectedMetricOutput.json"
            Required    = Test-Path "$testCase/ExpectedMetricOutput.json"
        }

        $currentTestCase.ExpectedOutputs += [ordered] @{
            OutputAlias = "NotificationOutput"
            FilePath    = "$testName/ExpectedNotificationOutput.json"
            Required    = Test-Path "$testCase/ExpectedNotificationOutput.json"
        }

        $testConfig.TestCases += $currentTestCase
    }

    $testConfigJson = ($testConfig | ConvertTo-Json -Depth 100).Replace("`r`n", "`n")
    Set-Content -Path $testConfigPath -Encoding utf8 -Value $testConfigJson
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

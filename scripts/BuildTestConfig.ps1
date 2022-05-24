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

function GenerateTestConfig($Scenario) {
    $TestConfigPath = "$Scenario/Test/testConfig.json"
    $ProjectPath = "$Scenario/asaproj.json"
    If (Test-Path $TestConfigPath) {
        rm $TestConfigPath
    }

    $TestConfig = [ordered] @{
        Script = "../$($Scenario.Name).asaql"
        TestCases = @()
    }

    foreach ($TestCase in (Get-ChildItem -Path "$Scenario/Test/*"  -Directory)) {
        $TestName = $TestCase.Name
        $TestConfig.TestCases += [ordered] @{
            Name = $TestName
            Inputs = @()
            ExpectedOutputs = @()
        }
        ForEach ($Input in (Get-ChildItem -Path "$Scenario/Inputs/*.json")) {
            $InputConfig = Get-Content -Raw -Path $Input | ConvertFrom-Json
            $InputAlias = $InputConfig.InputAlias
            $TestConfig.TestCases[-1].Inputs += [ordered] @{
                InputAlias = $InputAlias
                Type = $InputConfig.Type
                Format = "Json"
                FilePath = "$TestName/$InputAlias.json"
                ScriptType = "InputMock"
            }
        }

        $TestConfig.TestCases[-1].ExpectedOutputs += [ordered] @{
            OutputAlias = "MetricOutput"
            FilePath = "$TestName/ExpectedMetricOutput.json"
            Required = Test-Path "$TestCase/ExpectedMetricOutput.json"
        }

        $TestConfig.TestCases[-1].ExpectedOutputs += [ordered] @{
            OutputAlias = "NotificationOutput"
            FilePath = "$TestName/ExpectedNotificationOutput.json"
            Required = Test-Path "$TestCase/ExpectedNotificationOutput.json"
        }
    }

    $TestConfigJson = ($TestConfig | ConvertTo-Json -Depth 100).Replace("`r`n", "`n")
    Set-Content -Path $TestConfigPath -Encoding utf8 -Value $TestConfigJson
}

if ($Scenario) {
    GenerateTestConfig "$PSScriptRoot/../stream-analytics-queries/$Scenario"
}

else {
    foreach ($ScenarioPath in (Get-ChildItem -Path "$PSScriptRoot/../stream-analytics-queries/*" -Directory)) {
        GenerateTestConfig $ScenarioPath
    }
}

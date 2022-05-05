<#
.SYNOPSIS
    Run all Stream Analytics tests in the repository.

.PARAMETER Scenario
    Scenario name to run tests for.
    If not set, the script will run all tests found in the repository.
#>

#Requires -Version 7.0

param(
    [ValidateSet(
        'asset-maintenance',
        'machine-reporting-status'
    )]
    $Scenario
)

if (-not (Get-Command azure-streamanalytics-cicd -ErrorAction SilentlyContinue)) {
    throw "azure-streamanalytics-cicd is not installed, please install using NPM: npm install -g azure-streamanalytics-cicd"
}

function Resolve-PathSafely($Path) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

$TestOutputPath = Resolve-PathSafely -Path "$PSScriptRoot/../TestOutput"

function Invoke-Test($TestConfigPath) {
    if (-not (Test-Path -Path $TestConfigPath)) {
        throw "Could not find test config at $TestConfigPath"
    }

    # get project path by convention
    $projectPath = Resolve-Path "$TestConfigPath/../../asaproj.json"

    azure-streamanalytics-cicd test -project $projectPath -testConfigPath $TestConfigPath -outputPath $TestOutputPath
}

if ($Scenario) {
    $testConfigPath = Resolve-PathSafely -Path "$PSScriptRoot/../stream-analytics-queries/$Scenario/Test/testConfig.json"

    Invoke-Test -TestConfigPath $testConfigPath
} else {
    # Run all tests
    $testConfigs = Get-ChildItem -Recurse -Path "$PSScriptRoot/../stream-analytics-queries/*/testConfig.json"

    foreach ($testConfig in $testConfigs) {
        Invoke-Test -TestConfigPath $testConfig
    }
}

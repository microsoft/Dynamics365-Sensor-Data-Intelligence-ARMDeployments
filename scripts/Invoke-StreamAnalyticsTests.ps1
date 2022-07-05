<#
.SYNOPSIS
    Run Stream Analytics tests.

.PARAMETER Scenario
    Scenario name to run tests for.
    If not set, the script will run all tests found in the repository.
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

if (-not (Get-Command azure-streamanalytics-cicd -ErrorAction SilentlyContinue)) {
    throw "azure-streamanalytics-cicd is not installed, install using NPM: npm install -g azure-streamanalytics-cicd"
}

function Resolve-PathSafely($Path) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

$TestOutputPath = Resolve-PathSafely -Path "$PSScriptRoot/../TestOutput"

function Assert-ExpectedNotificationsContainRequiredProperties($TestConfigPath) {
    # Required from Logic App passing Notifications forward.
    $requiredProperties = @(
        'timestamp'
        'notificationType'
    )

    $projectDirectory = Resolve-Path "$TestConfigPath/../../"

    $expectedNotificationOutputPaths = Get-ChildItem -Path "$projectDirectory/Test/*/ExpectedNotificationOutput.json"

    foreach ($expectedNotificationOutputPath in $expectedNotificationOutputPaths) {
        $firstExpectedNotification = `
            Get-Content -Path $expectedNotificationOutputPath -Encoding utf8 -First 1 `
            | ConvertFrom-Json

        if (-not $firstExpectedNotification) {
            # no expected notifications
            continue
        }

        $notificationsMissingRequiredProperties = `
            $requiredProperties | Where-Object { -not $firstExpectedNotification."$_" }

        if ($notificationsMissingRequiredProperties) {
            $scenario = Split-Path $projectDirectory -Leaf
            throw "Notification output of $scenario is missing one or more columns of: `"$($requiredProperties -join '", "')`""
        }
    }
}

function Assert-MetricsContainRequiredColumns($TestConfigPath) {
    $requiredColumns = @(
        "DATEDIFF\(millisecond, CAST\('1970-01-01' AS datetime\), \w+\) AS uts" # unix epoch timestamp (in milliseconds)
        ' AS val' # float or integer value
    )

    $projectDirectory = Resolve-Path "$TestConfigPath/../../"

    $query = Get-Content -Path "$projectDirectory/*.asaql" -Raw

    $hasAnyMetricOutput = $query -match ' MetricOutput'
    if (-not $hasAnyMetricOutput) {
        return
    }

    $hasAllRequiredColumns = ($requiredColumns | ForEach-Object { $query -match "$_[,\s]" }) -notcontains $false

    if (-not $hasAllRequiredColumns) {
        $scenario = Split-Path $projectDirectory -Leaf
        throw "Metric output of $scenario is missing one or more columns of: `"$($requiredColumns -join '", "')`""
    }
}

function Invoke-Test($TestConfigPath) {
    if (-not (Test-Path -Path $TestConfigPath)) {
        throw "Could not find test config at $TestConfigPath"
    }

    Assert-ExpectedNotificationsContainRequiredProperties -TestConfigPath $TestConfigPath
    Assert-MetricsContainRequiredColumns -TestConfigPath $TestConfigPath

    # get project path, by convention it is 1 folder up from the test config file
    $projectPath = Resolve-Path "$TestConfigPath/../../asaproj.json"

    azure-streamanalytics-cicd test -project $projectPath -testConfigPath $TestConfigPath -outputPath $TestOutputPath
}

if ($Scenario) {
    $testConfigPath = Resolve-PathSafely -Path "$PSScriptRoot/../stream-analytics-queries/$Scenario/Test/testConfig.json"

    & "$PSScriptRoot/Build-StreamAnalyticsTestConfigurations.ps1" -Scenario $Scenario
    Invoke-Test -TestConfigPath $testConfigPath
}
else {
    # Run all tests
    $testConfigPaths = Get-ChildItem -Recurse -Path "$PSScriptRoot/../stream-analytics-queries/*/testConfig.json"

    & "$PSScriptRoot/Build-StreamAnalyticsTestConfigurations.ps1"
    foreach ($testConfigPath in $testConfigPaths) {
        Invoke-Test -TestConfigPath $testConfigPath
    }
}

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
        'asset-monitor',
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
$TestResultSummaryPath = Join-Path $TestOutputPath 'testResultSummary.json'

function Assert-TestRunSucceeded($TestConfigPath) {
    if (-not (Test-Path -Path $TestResultSummaryPath)) {
        throw "Expected test result summary was not found at $TestResultSummaryPath"
    }

    $testResultSummary = Get-Content -Path $TestResultSummaryPath -Raw -Encoding utf8 | ConvertFrom-Json
    if (-not $testResultSummary) {
        throw "Could not parse test result summary at $TestResultSummaryPath"
    }

    $failed = [int]$testResultSummary.Failed
    if ($failed -le 0) {
        return
    }

    $failedCases = @($testResultSummary.Results | Where-Object { $_.Status -ne 0 } | ForEach-Object { $_.Name })
    $scenario = Split-Path (Resolve-Path "$TestConfigPath/../../") -Leaf

    if ($failedCases.Count -gt 0) {
        throw "Stream Analytics tests failed for scenario '$scenario'. Failed: $failed. Cases: $($failedCases -join ', ')"
    }

    throw "Stream Analytics tests failed for scenario '$scenario'. Failed: $failed"
}

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

    Remove-Item -Path $TestResultSummaryPath -ErrorAction SilentlyContinue

    azure-streamanalytics-cicd test -project $projectPath -testConfigPath $TestConfigPath -outputPath $TestOutputPath

    if ($LASTEXITCODE -ne 0) {
        throw "azure-streamanalytics-cicd returned non-zero exit code: $LASTEXITCODE"
    }

    Assert-TestRunSucceeded -TestConfigPath $TestConfigPath
}

if ($Scenario) {
    $testConfigPaths = @(Resolve-PathSafely -Path "$PSScriptRoot/../stream-analytics-queries/$Scenario/Test/testConfig.json")

    & "$PSScriptRoot/Build-StreamAnalyticsTestConfigurations.ps1" -Scenario $Scenario
}
else {
    # Run all tests
    $testConfigPaths = Get-ChildItem -Recurse -Path "$PSScriptRoot/../stream-analytics-queries/*/testConfig.json"

    & "$PSScriptRoot/Build-StreamAnalyticsTestConfigurations.ps1"
}

$failures = @()
foreach ($testConfigPath in $testConfigPaths) {
    try {
        Invoke-Test -TestConfigPath $testConfigPath
    }
    catch {
        $failures += [pscustomobject]@{
            TestConfigPath = [string]$testConfigPath
            Message        = $_.Exception.Message
        }
        Write-Host "##[error] $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "=========================== Failure summary ===========================" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host " - $($failure.TestConfigPath)" -ForegroundColor Red
        Write-Host "     $($failure.Message)" -ForegroundColor Red
    }
    Write-Host "=======================================================================" -ForegroundColor Red

    throw "$($failures.Count) Stream Analytics test run(s) failed. See summary above."
}

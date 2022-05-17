# Contributing

This page lists details on how to work with artifacts in this repository.

## Development environment

The easiest way to get started developing in this repository is to create a [Codespace](#codespaces) for yourself.

### Codespaces

This repository is configured to work out-of-the-box with Codespaces.

Learn more [here](https://docs.github.com/codespaces/getting-started/quickstart).

### Local development

You need the following dependencies installed locally to build the ARM template and test scenario queries.

1. [PWSH](https://docs.microsoft.com/powershell/scripting/install/installing-powershell) version 7 or higher.
1. [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) (`az`, not the Azure PowerShell modules).
1. (To run tests) `azure-streamanalytics-cicd` installed globally (requires [Node and NPM](https://nodejs.org/)).

    ```bash
    npm install -g azure-streamanalytics-cicd
    ```

## Working on scenario stream analytics queries

### Run query locally

Install [extension](https://marketplace.visualstudio.com/items?itemName=ms-bigdatatools.vscode-asa) to VS Code and you can click "Run locally" above the query (IntelliSense).

### Testing

#### Run tests

Run the script [`Invoke-StreamAnalyticsTests.ps1`](./scripts/Invoke-StreamAnalyticsTests.ps1) to run all tests. The script can be invoked with a `-Scenario` parameter, choosing one of the scenarios implemented in this solution.

#### Add a new test case

New test cases can be added using [`azure-streamanalytics-cicd addtestcase`](https://docs.microsoft.com/azure/stream-analytics/cicd-tools?tabs=visual-studio-code#add-a-test-case), or by modifying the `testConfig.json` file in `/Test` folder under a scenario, and add new elements to the array of the `TestCases` property.

## Working on Bicep template

* If any new parameters are added, make sure to also add corresponding parameters to [`createUiDefinition.json`](./createUiDefinition.json).

### Building ARM template

Run the script [`Build-ARMTemplate.ps1`](./scripts/Build-ARMTemplate.ps1) to build [`azuredeploy.json`](./azuredeploy.json) from the current [`main.bicep`](./main.bicep).

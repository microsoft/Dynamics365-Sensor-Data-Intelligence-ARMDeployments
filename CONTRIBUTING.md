# Contributing

This page lists details on how to work with artifacts in this repository.

## Prerequisites

1. [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli).
1. [Node and NPM](https://nodejs.org/).
1. `azure-streamanalytics-cicd` installed globally.

    ```bash
    npm install -g azure-streamanalytics-cicd
    ```

## Working on scenario stream analytics queries

### Testing

#### Run tests

Run the script [`Invoke-StreamAnalyticsTests.ps1`](./scripts/Invoke-StreamAnalyticsTests.ps1) to run all tests. The script can be invoked with a `-Scenario` parameter, choosing one of the scenarios implemented in this solution.

#### Add a new test

Modify `testConfig.json` file in the `/Test` folder under a scenario, and add new elements to the array of the `TestCases` property.

## Working on Bicep template

* If any new `param`eters are added, make sure to also add corresponding parameters to [`createUiDefinition.json`](./createUiDefinition.json).

### Building ARM template

Run the script [`Build-ARMTemplate.ps1`](./scripts/Build-ARMTemplate.ps1) to build [`azuredeploy.json`](./azuredeploy.json) from the current [`main.bicep`](./main.bicep).

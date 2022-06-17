# Contributing

This page lists details on how to work with artifacts in this repository.

## Table of contents

- [Contributing](#contributing)
  - [Table of contents](#table-of-contents)
  - [Developing](#developing)
    - [Codespaces](#codespaces)
    - [Local development](#local-development)
    - [Adding a new scenario](#adding-a-new-scenario)
  - [Working with Logic Apps](#working-with-logic-apps)
  - [Working on scenario stream analytics queries](#working-on-scenario-stream-analytics-queries)
    - [Run query locally](#run-query-locally)
    - [Testing](#testing)
      - [Run tests](#run-tests)
      - [Add a new test case](#add-a-new-test-case)
  - [Working on Bicep template](#working-on-bicep-template)
    - [Building ARM template](#building-arm-template)
    - [Resolving `azuredeploy.json` merge conflict](#resolving-azuredeployjson-merge-conflict)
  - [Working with custom ARM deployment UI](#working-with-custom-arm-deployment-ui)

## Developing

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

### Adding a new scenario

To add a new Sensor Data Intelligence scenario, at least the following steps must be performed:

1. Azure Stream Analytics query: Add a new folder in [`stream-analytics-queries`](./stream-analytics-queries/) for the new scenario- similar to the other scenarios, then a new `<scenario-name>.asaql` file containing the query.
1. Add the new scenario in [`main.bicep`](./main.bicep)'s `streamScenarioJobs` variable (object array). Values for `referenceDataName` and `referencePathPattern` used here must also be used in the reference data Logic Apps (pull and clean).
1. Add branches to the Logic Apps for [pulling reference data](./logic-apps/pull-reference-data.json) and [cleaning outdated reference data](./logic-apps/clean-reference-data.json) to cover the new scenario.

## Working with Logic Apps

The most effective way to work with and make changes to the Logic Apps in this repository is to deploy `azuredeploy.json` to Azure, make changes in the Logic App designer, then copy the Code definition into the corresponding Logic App JSON file under [`logic-apps`](./logic-apps/).

To get the code for a Logic App, click the `Code` button:
![Image showing the location of the Code button in the Logic Apps designer](https://user-images.githubusercontent.com/639843/174291285-6c334c96-4f1f-4f5e-93ec-524c5fe48efd.png)

The `Build-ARMTemplate.ps1` script will prune secrets from the Logic App parameters, so make sure to run that before Git-committing changes.

## Working on scenario stream analytics queries

### Run query locally

Install [extension](https://marketplace.visualstudio.com/items?itemName=ms-bigdatatools.vscode-asa) to VS Code and you can click "Run locally" above the query (IntelliSense).

### Testing

#### Run tests

Run the script [`Invoke-StreamAnalyticsTests.ps1`](./scripts/Invoke-StreamAnalyticsTests.ps1) to run all tests. The script can be invoked with a `-Scenario` parameter, choosing one of the scenarios implemented in this solution.

#### Add a new test case

New test cases can be added by creating a new folder inside the "Test" folder of the scenario to be tested. The name of the folder will be the name of the test. Add json files that fit the names of the inputs to the stream.
Also add a file with the name "ExpectedMetricOutput.json" and/or "ExpectedNotificationOutput.json", depending on the test. The "testConfig.json" in the "Test" folder file will be automatically updated when the tests are run.
Any manual changes to it will be overwritten!

## Working on Bicep template

If any new parameters are added, make sure to also add corresponding parameters to [`createUiDefinition.json`](./createUiDefinition.json).

### Building ARM template

Run the script [`Build-ARMTemplate.ps1`](./scripts/Build-ARMTemplate.ps1) to build [`azuredeploy.json`](./azuredeploy.json) from the current [`main.bicep`](./main.bicep).

### Resolving `azuredeploy.json` merge conflict

If `main` has changed and you need to pull in those changes to your branch, you will most likely get a merge conflict on the file [`azuredeploy.json`](./azuredeploy.json). Do not waste time resolving the conflicts- simply invoke [`Build-ARMTemplate.ps1`](./scripts/Build-ARMTemplate.ps1) after resolving conflicts in any other files- then the [`azuredeploy.json`](./azuredeploy.json) file will be updated to reflect changes from both `main` and your branch (without any merge conflicts).

## Working with custom ARM deployment UI

Find general documentation on how to work with the [`createUiDefinition.json`](./createUiDefinition.json) at [Azure Documentation](https://docs.microsoft.com/azure/azure-resource-manager/managed-applications/create-uidefinition-overview).

To find a list of available user interface elements, see [this](https://docs.microsoft.com/azure/azure-resource-manager/managed-applications/create-uidefinition-elements).

Changes to the UI definition can be tested in the [createUiDefinition sandbox](https://portal.azure.com/?feature.customPortal=false#view/Microsoft_Azure_CreateUIDef/SandboxBlade).

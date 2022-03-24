# Introduction

This repository is not intended to ever be released or made public. The artifacts here should be migrated to https://github.com/Azure/azure-quickstart-templates/tree/master/application-workloads on release.

To compile the Bicep file to ARM, you need to install AZ CLI (https://docs.microsoft.com/en-us/cli/azure/install-azure-cli).

What follows is the `README.md` contents that we should put in the `azure-quickstart-templates` repository:

# Baseline Dynamics 365 SCM Sensor Data Intelligence Azure Resource Deployment

![Azure Public Test Date](https://azurequickstartsservice.blob.core.windows.net/badges/path-to-sample/PublicLastTestDate.svg)
![Azure Public Test Result](https://azurequickstartsservice.blob.core.windows.net/badges/path-to-sample/PublicDeployment.svg)

![Azure US Gov Last Test Date](https://azurequickstartsservice.blob.core.windows.net/badges/path-to-sample/FairfaxLastTestDate.svg)
![Azure US Gov Last Test Result](https://azurequickstartsservice.blob.core.windows.net/badges/path-to-sample/FairfaxDeployment.svg)

![Best Practice Check](https://azurequickstartsservice.blob.core.windows.net/badges/path-to-sample/BestPracticeResult.svg)
![Cred Scan Check](https://azurequickstartsservice.blob.core.windows.net/badges/path-to-sample/CredScanResult.svg)

![Bicep Version](https://azurequickstartsservice.blob.core.windows.net/badges/path-to-sample/BicepVersion.svg)

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2Fazure-quickstart-templates%2Fmaster%2Fpath-to-sample%2Fazuredeploy.json)

[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2Fazure-quickstart-templates%2Fmaster%2Fpath-to-sample%2Fazuredeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2Fazure-quickstart-templates%2Fmaster%2Fpath-to-sample%2Fazuredeploy.json)

This template deploys a set of baseline Azure resources for use in Dynamics 365 SCM Sensor Data Intelligence. Sensor Data Intelligence consumes output from an insights layer (Stream Analytics) to notify and affect business processes in Dynamics 365.

The template can reuse an existing IoT Hub from a previous [Connected Field Service](https://docs.microsoft.com/en-us/dynamics365/field-service/connected-field-service) Azure resources deployment.

## Overview and deployed resources

The following resources are deployed as part of the solution:

- Azure IoT Hub: sink for IoT signals
- Azure Stream Analytics job: for transforming IoT signals into insight signals
- Azure Cache for Redis: for real-time sensor metric visualizations in Dynamics
- Azure Function: for updating the Redis cache with sensor metrics
  - With an App Service plan
- Azure Storage Account: for storing reference data from Dynamics and `AzureWebJobsStorage` target for the Azure Function
- Azure Service Bus: for storing insight signals received from Stream Analytics to be sent to Dynamics
- Azure Logic Apps: for updating reference data in blobs from-, and forwarding insight signals from Service Bus to, Dynamics
- User assigned managed identity: for securely communicating with Dynamics from Logic apps

## Prerequisites

It is expected that the entity deploying this already has some IoT systems emitting telemetry to be captured. If not, IoT simulators can be used to generate data for testing and validation.

## Deployment steps

You can click the "Deploy to Azure" button at the beginning of this document.

## Usage

It is expected that this solution will be used from within Dynamics 365, for Sensor Data Intelligence.

### Connect

After deployment, you must allowlist the deployed user assigned managed identity's client ID in Dynamics.

### Customize

After deployment, you will want to make changes to the Azure Stream Analytics job query (transform) to fit your IoT sensor telemetry into an expected shape.

## Notes

It is not recommended to reuse the Stream Analytics job between Connected Field Service and Dynamics SCM Sensor Data Intelligence, as they will evolve independently and can clash if breaking changes are applied in one or the other.

This template is a baseline and is purposefully made simple. This means that; before going into production, you should go over the individually deployed resources and make sure that they are configured securely to the specifications of your organization.

`Tags: Dynamics 365, Sensor Data Intelligence, IoT`

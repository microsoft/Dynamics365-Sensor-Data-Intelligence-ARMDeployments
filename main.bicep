@description('If you have an existing IoT Hub from Connected Field Services, you can reuse it. If set to False, the template will create a fresh IoT Hub.')
param reuseExistingIotHub bool = false

@description('Resource group name of the IoT Hub to reuse. Mandatory if "Reuse Existing Iot Hub" is set to True.')
param existingIotHubResourceGroupName string = ''

@description('Resource name of the IoT Hub to reuse. Mandatory if "Reuse Existing Iot Hub" is set to True.')
param existingIotHubName string = ''

#disable-next-line no-loc-expr-outside-params
var resourcesLocation = resourceGroup().location

var uniqueIdentifier = uniqueString(resourceGroup().id)

resource redis 'Microsoft.Cache/Redis@2021-06-01' = {
  name: 'msdyn-iiot-sdi-redis-${uniqueIdentifier}'
  location: resourcesLocation
  properties: {
    redisVersion: '4.1.14'
    sku: {
      name: 'Basic'
      family: 'C'
      capacity: 0
    }
  }
}

resource newIotHub 'Microsoft.Devices/IotHubs@2021-07-02' = if (!reuseExistingIotHub) {
  name: 'msdyn-iiot-sdi-iothub-${uniqueIdentifier}'
  location: resourcesLocation
  sku: {
    // Only 1 free per subscription is allowed.
    // To avoid deployment failures due to this: default to B1.
    name: 'B1'
    capacity: 1
  }
}

resource existingIotHub 'Microsoft.Devices/IotHubs@2021-07-02' existing = if (reuseExistingIotHub) {
  name: existingIotHubName
  scope: resourceGroup(existingIotHubResourceGroupName)
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: 'msdyniiotst${uniqueIdentifier}'
  location: resourcesLocation
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
  }

  resource blobServices 'blobServices' = {
    name: 'default'

    resource iotOutputDataBlobContainer 'containers' = {
      name: 'iotoutputstoragev2'
    }

    resource referenceDataBlobContainer 'containers' = {
      name: 'iotreferencedatastoragev2'
    }
  }
}

resource asaToDynamicsServiceBus 'Microsoft.ServiceBus/namespaces@2021-11-01' = {
  name: 'msdyn-iiot-sdi-signalbus-${uniqueIdentifier}'
  location: resourcesLocation
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    disableLocalAuth: true // disable SAS access
  }

  resource outboundInsightsQueue 'queues@2021-06-01-preview' = {
    name: 'outbound-insights'
    properties: {
      enablePartitioning: false
      enableBatchedOperations: true
    }
  }
}

resource asaToRedisFuncHostingPlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: 'msdyn-iiot-sdi-appsvcplan-${uniqueIdentifier}'
  location: resourcesLocation
  sku: {
    name: 'F1'
    capacity: 0
  }
}

resource asaToRedisFuncSite 'Microsoft.Web/sites@2021-03-01' = {
  name: 'msdyn-iiot-sdi-functionapp-${uniqueIdentifier}'
  location: resourcesLocation
  kind: 'functionapp'
  properties: {
    serverFarmId: asaToRedisFuncHostingPlan.id
    siteConfig: {
      ftpsState: 'Disabled'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          // The default value for this is ~1. When setting to >=~2 in a nested Web/sites/config resource,
          // the existing keys are rotated. From this, a risk follows that the following listKeys API
          // will return the keys from before rotating the keys (i.e., a race condition):
          // listKeys('${asaToRedisFuncSite.id}/host/default', '2021-02-01').functionKeys['default']
          // Setting the value within the initial Web/sites resource deployment avoids this issue.
          // See: https://stackoverflow.com/a/52923874/618441 for more details.
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'RedisConnectionString'
          value: '${redis.properties.hostName}:${redis.properties.sslPort},password=${redis.listKeys().primaryKey},ssl=True,abortConnect=False'
        }
      ]
    }
  }

  resource deployAsaToRedisFunctionFromGitHub 'sourcecontrols' = {
    name: 'web'
    kind: 'gitHubHostedTemplate'
    dependsOn: [
      appDeploymentWait
    ]
    properties: {
      repoUrl: 'https://github.com/AndreasHassing/AzureStreamAnalyticsToRedisFunction'
      branch: 'main'
      isManualIntegration: true
    }
  }
}

// Wait a number of seconds after FunctionApp deployment until attempting to deploy from GitHub.
// This attempts to avoid a known race condition in Azure ARM deployments of Azure Functions
// where any attempt to act on a created Azure Function can fail if it is restarting (it can do
// multiple restarts during initial creation).
resource appDeploymentWait 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'appDeploymentWait'
  location: resourcesLocation
  kind: 'AzurePowerShell'
  dependsOn: [
    asaToRedisFuncSite
  ]
  properties: {
    retentionInterval: 'PT1H'
    azPowerShellVersion: '7.3.2'
    scriptContent: 'Start-Sleep -Seconds 30'
  }
}

resource streamAnalytics 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: 'msdyn-iiot-sdi-stream-analytics-${uniqueIdentifier}'
  location: resourcesLocation
  dependsOn: [
    // Deploying the Git repo restarts the host runtime which can fail listKeys invocations,
    // so wait and ensure the git repository is fully deployed before attempting to deploy ASA.
    asaToRedisFuncSite::deployAsaToRedisFunctionFromGitHub
  ]
  properties: {
    sku: {
      name: 'Standard'
    }
    compatibilityLevel: '1.2'
    outputStartMode: 'JobStartTime'
    inputs: [
      {
        name: 'IotInput'
        properties: {
          type: 'Stream'
          datasource: {
            type: 'Microsoft.Devices/IotHubs'
            properties: {
              iotHubNamespace: reuseExistingIotHub ? existingIotHub.name : newIotHub.name
              sharedAccessPolicyName: reuseExistingIotHub ? existingIotHub.listkeys().value[0].keyName : newIotHub.listkeys().value[0].keyName
              sharedAccessPolicyKey: reuseExistingIotHub ? existingIotHub.listkeys().value[0].primaryKey : newIotHub.listkeys().value[0].primaryKey
              endpoint: 'messages/events'
              consumerGroupName: '$Default'
            }
          }
          serialization: {
            type: 'Json'
            properties: {
              encoding: 'UTF8'
            }
          }
        }
      }
      {
        name: 'MachineJobHistoryReferenceInput'
        properties: {
          type: 'Reference'
          datasource: {
            type: 'Microsoft.Storage/Blob'
            properties: {
              storageAccounts: [
                {
                  accountName: storageAccount.name
                  accountKey: storageAccount.listKeys().keys[0].value
                }
              ]
              container: storageAccount::blobServices::referenceDataBlobContainer.name
              pathPattern: 'machinereportingstatus/ReferenceDataMachineJobHistory.csv'
            }
          }
          serialization: {
            type: 'Csv'
            properties: {
              fieldDelimiter: ','
              encoding: 'UTF8'
            }
          }
        }
      }
      {
        name: 'ReportingStatusReferenceInput'
        properties: {
          type: 'Reference'
          datasource: {
            type: 'Microsoft.Storage/Blob'
            properties: {
              storageAccounts: [
                {
                  accountName: storageAccount.name
                  accountKey: storageAccount.listKeys().keys[0].value
                }
              ]
              container: storageAccount::blobServices::referenceDataBlobContainer.name
              pathPattern: 'machinereportingstatus/ReferenceDataMachineReportingStatus.csv'
            }
          }
          serialization: {
            type: 'Csv'
            properties: {
              fieldDelimiter: ','
              encoding: 'UTF8'
            }
          }
        }
      }
    ]
    outputs: [
      {
        name: 'MetricOutput'
        properties: {
          datasource: {
            type: 'Microsoft.AzureFunction'
            properties: {
              functionAppName: asaToRedisFuncSite.name
              functionName: 'AzureStreamAnalyticsToRedis'
              apiKey: listKeys('${asaToRedisFuncSite.id}/host/default', '2021-02-01').functionKeys['default']
            }
          }
        }
      }
      {
        name: 'ServiceBusOutput'
        properties: {
          datasource: {
            type: 'Microsoft.ServiceBus/Queue'
            properties: {
              serviceBusNamespace: asaToDynamicsServiceBus.name
              queueName: asaToDynamicsServiceBus::outboundInsightsQueue.name
              authenticationMode: 'ConnectionString'
              sharedAccessPolicyKey: asaToDynamicsServiceBus.listkeys() // TODO
            }
          }
        }
      }
    ]
    transformation: {
      name: 'input2output'
      properties: {
        query: '''
SELECT *
INTO MetricOutput
FROM IotInput
        '''
      }
    }
  }
}

resource logicAppToDynamicsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'msdyn-iiot-sdi-identity-${uniqueIdentifier}'
  location: resourcesLocation
}

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'msdyn-iiot-sdi-logicapps-${uniqueIdentifier}'
  location: resourcesLocation
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${logicAppToDynamicsIdentity.id}': {}
    }
  }
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        RecurrenceName: {
          type: 'Recurrence'
          recurrence: {
            frequency: 'Minute'
            interval: 3
          }
        }
      }
      actions: {
        HTTPSample: {
          type: 'Http'
          runAfter: {}
          inputs: {
            method: 'GET'
            // TODO (anniels 2022-03-18) needs to be the reference data OData endpoint
            uri: 'https://sensor-data-v2.sandbox.operations.test.dynamics.com/data/Customers'
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: logicAppToDynamicsIdentity.id
              // Microsoft.ERP first-party app, works for all FnO environments.
              audience: '00000015-0000-0000-c000-000000000000'
            }
          }
        }
      }
    }
  }
}

@description('AAD Application ID to allowlist in Dynamics')
output applicationId string = logicAppToDynamicsIdentity.properties.clientId

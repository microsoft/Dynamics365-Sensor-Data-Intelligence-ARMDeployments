@description('Resource group name of the IoT Hub to reuse. Leave empty to create a new IoT Hub.')
param existingIotHubResourceGroupName string = ''

@description('Resource name of the IoT Hub to reuse. Leave empty to create a new IoT Hub.')
param existingIotHubName string = ''

#disable-next-line no-loc-expr-outside-params
var resourcesLocation = resourceGroup().location

var uniqueIdentifier = uniqueString(resourceGroup().id)

var createNewIotHub = empty(existingIotHubName)

var azureServiceBusDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'

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

resource newIotHub 'Microsoft.Devices/IotHubs@2021-07-02' = if (createNewIotHub) {
  name: 'msdyn-iiot-sdi-iothub-${uniqueIdentifier}'
  location: resourcesLocation
  sku: {
    // Only 1 free per subscription is allowed.
    // To avoid deployment failures due to this: default to B1.
    name: 'B1'
    capacity: 1
  }
}

resource existingIotHub 'Microsoft.Devices/IotHubs@2021-07-02' existing = if (!createNewIotHub) {
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
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    // Cannot disable public network access as the Azure Function needs it.
    // Cannot configure denyall ACLs as VNets are not supported for ASA jobs.
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

resource asaToDynamicsServiceBus 'Microsoft.ServiceBus/namespaces@2021-06-01-preview' = {
  name: 'msdyn-iiot-sdi-servicebus-${uniqueIdentifier}'
  location: resourcesLocation
  sku: {
    // only premium tier allows IP firewall rules
    // https://docs.microsoft.com/azure/service-bus-messaging/service-bus-ip-filtering
    name: 'Basic'
    tier: 'Basic'
  }

  resource outboundInsightsQueue 'queues' = {
    name: 'outbound-insights'
    properties: {
      enablePartitioning: false
      enableBatchedOperations: true
    }

    resource asaSendAuthorizationRule 'authorizationRules' = {
      name: 'AsaSendRule'
      properties: {
        rights: [
          'Send'
        ]
      }
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
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
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
  // It is not possible to put an Azure Stream Analytics (ASA) job in a Virtual Network
  // without using a dedicated ASA cluster. ASA clusters have a higher base cost compared
  // to individual jobs, but should be considered for production- as it enables VNET isolation.
  name: 'msdyn-iiot-sdi-stream-analytics-${uniqueIdentifier}'
  location: resourcesLocation
  identity: {
    type: 'SystemAssigned'
  }
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
              iotHubNamespace: createNewIotHub ? newIotHub.name : existingIotHub.name
              sharedAccessPolicyName: createNewIotHub ? newIotHub.listkeys().value[0].keyName : existingIotHub.listkeys().value[0].keyName
              sharedAccessPolicyKey: createNewIotHub ? newIotHub.listkeys().value[0].primaryKey : existingIotHub.listkeys().value[0].primaryKey
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
              authenticationMode: 'Msi'
              storageAccounts: [
                {
                  accountName: storageAccount.name
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
              authenticationMode: 'Msi'
              storageAccounts: [
                {
                  accountName: storageAccount.name
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
              // ASA does not yet support 'Msi' authentication mode for Service Bus output
              authenticationMode: 'ConnectionString'
              sharedAccessPolicyName: asaToDynamicsServiceBus::outboundInsightsQueue::asaSendAuthorizationRule.listKeys().keyName
              sharedAccessPolicyKey: asaToDynamicsServiceBus::outboundInsightsQueue::asaSendAuthorizationRule.listKeys().primaryKey
            }
          }
          serialization: {
            type: 'Json'
            properties: {
              encoding: 'UTF8'
              format: 'Array'
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

resource sharedLogicAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'msdyn-iiot-sdi-identity-${uniqueIdentifier}'
  location: resourcesLocation
}

// Logic App currently does not support multiple user assigned managed identities, so we have to settle for
// a single one for both communicating with the AOS and ServiceBus.
resource serviceBusReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  // do not assign to queue scope, as we only have 1 queue and the Logic App queue name drop down does not work at that scope level
  scope: asaToDynamicsServiceBus
  name: guid(asaToDynamicsServiceBus::outboundInsightsQueue.id, sharedLogicAppIdentity.id, azureServiceBusDataReceiverRoleId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', azureServiceBusDataReceiverRoleId)
    principalId: sharedLogicAppIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'For letting ${sharedLogicAppIdentity.name} read from Service Bus queues.'
  }
}

resource refDataLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'msdyn-iiot-sdi-logicapp-refdata-${uniqueIdentifier}'
  location: resourcesLocation
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${sharedLogicAppIdentity.id}': {}
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
              identity: sharedLogicAppIdentity.id
              // Microsoft.ERP first-party app, works for all FnO environments.
              audience: '00000015-0000-0000-c000-000000000000'
            }
          }
        }
      }
    }
  }
}

resource logicApp2ServiceBusConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'msdyn-iiot-sdi-servicebusconnection-${uniqueIdentifier}'
  location: resourcesLocation
  properties: {
    displayName: 'msdyn-iiot-sdi-servicebusconnection-${uniqueIdentifier}'
    #disable-next-line BCP089 Bicep does not know the parameterValueSet property for connections
    parameterValueSet: {
      name: 'managedIdentityAuth'
      values: {
        namespaceEndpoint: {
          value: asaToDynamicsServiceBus.properties.serviceBusEndpoint
        }
      }
    }
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', resourcesLocation, 'servicebus')
      type: 'Microsoft.Web/locations/managedApis'
    }
  }
}

resource notificationLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'msdyn-iiot-sdi-logicapp-notification-${uniqueIdentifier}'
  location: resourcesLocation
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${sharedLogicAppIdentity.id}': {}
    }
  }
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'When_a_message_is_received_in_a_queue_(auto-complete)': {
          type: 'ApiConnection'
          recurrence: {
            frequency: 'Second'
            interval: 30
          }
          inputs: {
            host: {
              connection: {
                name: '''@parameters('$connections')['servicebus']['connectionId']'''
              }
            }
            method: 'get'
            path: '/@{encodeURIComponent(encodeURIComponent(\'${asaToDynamicsServiceBus::outboundInsightsQueue.name}\'))}/messages/head'
            queries: {
              queryType: 'Main'
            }
          }
        }
      }
      actions: {
        HTTPSample: {
          type: 'Http'
          runAfter: {}
          inputs: {
            method: 'POST'
            // TODO (anniels 2022-03-18) needs to be the reference data OData endpoint
            uri: 'https://sensor-data-v2.sandbox.operations.test.dynamics.com/data/Customers'
            body: '''@triggerBody()?['ContentData']'''
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: sharedLogicAppIdentity.id
              // Microsoft.ERP first-party app, works for all FnO environments.
              audience: '00000015-0000-0000-c000-000000000000'
            }
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          servicebus: {
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', resourcesLocation, 'servicebus')
            connectionId: logicApp2ServiceBusConnection.id
            connectionName: 'servicebus'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
                identity: sharedLogicAppIdentity.id
              }
            }
          }
        }
      }
    }
  }
}

@description('AAD Application ID to allowlist in Dynamics')
output applicationId string = sharedLogicAppIdentity.properties.clientId

@description('(Required) URL of the Dynamics 365 environment (example: https://contoso-uat.sandbox.operations.dynamics.com/)')
param environmentUrl string = 'http://contoso-uat.sandbox.operations.dynamics.com/'

@description('Resource group name of the IoT Hub to reuse. Leave empty to create a new IoT Hub.')
param existingIotHubResourceGroupName string = ''

@description('Resource name of the IoT Hub to reuse. Leave empty to create a new IoT Hub.')
param existingIotHubName string = ''

#disable-next-line no-loc-expr-outside-params
var resourcesLocation = resourceGroup().location

var uniqueIdentifier = uniqueString(resourceGroup().id)

var createNewIotHub = empty(existingIotHubName)

var azureServiceBusDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'

var azureStorageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

var trimmedEnvironmentUrl = trim(environmentUrl)

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
  properties: {
    // minTlsVersion is not available in popular regions, cannot enable broadly
    // minTlsVersion: '1.2'
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
      name: 'sensorintelligencereferencedata'
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

var streamScenarioJobs = [
  {
    scenario: 'machine-reporting-status'
    referenceDataName: 'SensorJobsReferenceInput'
    referencePathPattern: 'sensorjobs/sensorjobs{date}T{time}.json'
    query: loadTextContent('stream-analytics-queries/machine-reporting-status/machine-reporting-status.asaql')
  }
  {
    scenario: 'asset-maintenance'
    referenceDataName: 'ScenarioMappings'
    referencePathPattern: 'assetmaintenancedata/assetmaintanence{date}T{time}.json'
    query: loadTextContent('stream-analytics-queries/asset-maintenance/asset-maintenance.asaql')
  }
  {
    scenario: 'product-quality-validation'
    referenceDataName: 'SensorJobItemBatchAttributeReferenceInput'
    referencePathPattern: 'sensorjobbatchattributes/sensorjobitembatchattributemappings{date}T{time}.json'
    query: loadTextContent('stream-analytics-queries/product-quality-validation/product-quality-validation.asaql')
  }
]
resource streamAnalyticsJobs 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = [for job in streamScenarioJobs: {
  // It is not possible to put an Azure Stream Analytics (ASA) job in a Virtual Network
  // without using a dedicated ASA cluster. ASA clusters have a higher base cost compared
  // to individual jobs, but should be considered for production- as it enables VNET isolation.
  name: 'msdyn-iiot-sdi-${job.scenario}-${uniqueIdentifier}'
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
              // listkeys().value[1] == service policy, which is less privileged than listkeys().value[0] (iot hub owner)
              // unless user's existing iot hub policies list is modified; in which case they must go into ASA
              // and pick a concrete key to use for the IoT Hub input.
              sharedAccessPolicyName: createNewIotHub ? newIotHub.listkeys().value[1].keyName : existingIotHub.listkeys().value[1].keyName
              sharedAccessPolicyKey: createNewIotHub ? newIotHub.listkeys().value[1].primaryKey : existingIotHub.listkeys().value[1].primaryKey
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
        name: job.referenceDataName
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
              pathPattern: job.referencePathPattern
              dateFormat: 'yyyy-MM-dd'
              timeFormat: 'HH-mm'
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
        name: 'NotificationOutput'
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
        query: job.query
      }
    }
  }
}]

resource sharedLogicAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'msdyn-iiot-sdi-identity-${uniqueIdentifier}'
  location: resourcesLocation
}

// Logic App currently does not support multiple user assigned managed identities,
// so we use a single one for both communicating with the AOS and ServiceBus.
resource serviceBusReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  // do not assign to queue scope as the Logic App queue name drop down does not work at that scope level (it's OK since we only have 1 queue)
  scope: asaToDynamicsServiceBus
  name: guid(asaToDynamicsServiceBus::outboundInsightsQueue.id, sharedLogicAppIdentity.id, azureServiceBusDataReceiverRoleId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', azureServiceBusDataReceiverRoleId)
    principalId: sharedLogicAppIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'For letting ${sharedLogicAppIdentity.name} read from Service Bus queues.'
  }
}

resource sharedLogicAppBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  scope: storageAccount
  name: guid(storageAccount.id, sharedLogicAppIdentity.id, azureStorageBlobDataContributorRoleId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', azureStorageBlobDataContributorRoleId)
    principalId: sharedLogicAppIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'For letting ${sharedLogicAppIdentity.name} insert blobs into the reference data Storage Account.'
  }
}

resource streamAnalyticsBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = [for i in range(0, length(streamScenarioJobs)): {
  scope: storageAccount
  name: guid(storageAccount.id, streamAnalyticsJobs[i].id, azureStorageBlobDataContributorRoleId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', azureStorageBlobDataContributorRoleId)
    principalId: streamAnalyticsJobs[i].identity.principalId
    principalType: 'ServicePrincipal'
    description: 'For letting ${streamAnalyticsJobs[i].name} read from the reference data Storage Account. Stream Analytics needs Contributor role to function, even if it only reads.'
  }
}]

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
          value: replace(replace(asaToDynamicsServiceBus.properties.serviceBusEndpoint, 'https://', 'sb://'), ':443', '')
        }
      }
    }
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', resourcesLocation, 'servicebus')
      type: 'Microsoft.Web/locations/managedApis'
    }
  }
}

resource logicApp2StorageAccountConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'msdyn-iiot-sdi-storageaccountconnection-${uniqueIdentifier}'
  location: resourcesLocation
  properties: {
    displayName: 'msdyn-iiot-sdi-storageaccountbusconnection-${uniqueIdentifier}'
    #disable-next-line BCP089 Bicep does not know the parameterValueSet property for connections
    parameterValueSet: {
      name: 'managedIdentityAuth'
      values: {}
    }
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', resourcesLocation, 'azureblob')
      type: 'Microsoft.Web/locations/managedApis'
    }
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
    definition: json(loadTextContent('logic-apps/pull-reference-data.json')).definition
    parameters: {
      '$connections': {
        value: {
          azureblob: {
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', resourcesLocation, 'azureblob')
            connectionId: logicApp2StorageAccountConnection.id
            connectionName: 'azureblob'
            connectionProperties: {
              authentication: {
                identity: sharedLogicAppIdentity.id
                type: 'ManagedServiceIdentity'
              }
            }
          }
        }
      }
      DynamicsIdentityAuthentication: {
        value: {
          audience: '00000015-0000-0000-c000-000000000000'
          identity: sharedLogicAppIdentity.id
          type: 'ManagedServiceIdentity'
        }
      }
      EnvironmentUrl: {
        value: trimmedEnvironmentUrl
      }
      StorageAccountName: {
        value: storageAccount.name
      }
    }
    accessControl: {
      contents: {
        allowedCallerIpAddresses: [
          {
            // See https://aka.ms/tmt-th188 for details.
            addressRange: '0.0.0.0-0.0.0.0'
          }
        ]
      }
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
    definition: json(loadTextContent('logic-apps/push-notification.json')).definition
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
      DynamicsIdentityAuthentication: {
        value: {
          audience: '00000015-0000-0000-c000-000000000000'
          identity: sharedLogicAppIdentity.id
          type: 'ManagedServiceIdentity'
        }
      }
      EnvironmentUrl: {
        value: trimmedEnvironmentUrl
      }
    }
    accessControl: {
      contents: {
        allowedCallerIpAddresses: [
          {
            // See https://aka.ms/tmt-th188 for details.
            addressRange: '0.0.0.0-0.0.0.0'
          }
        ]
      }
    }
  }
}

@description('AAD Application ID to allowlist in Dynamics')
output applicationId string = sharedLogicAppIdentity.properties.clientId

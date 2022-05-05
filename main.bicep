@description('URL of the Dynamics 365 environment (example: https://contoso.operations.dynamics.com/)')
@minLength(1) // mandatory
param environmentUrl string = ''

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
        name: 'SensorJobsReferenceInput'
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
              pathPattern: 'sensorjobs/sensorjobs{date}T{time}.json'
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
        query: loadTextContent('stream-analytics-queries/machine-reporting-status/machine-reporting-status.asaql')
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

resource streamAnalyticsBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  scope: storageAccount
  name: guid(storageAccount.id, streamAnalytics.id, azureStorageBlobDataContributorRoleId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', azureStorageBlobDataContributorRoleId)
    principalId: streamAnalytics.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'For letting ${streamAnalytics.name} read from the reference data Storage Account. Stream Analytics needs Contributor role to function, even if it only reads.'
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
        Recurrence: {
          recurrence: {
            frequency: 'Minute'
            interval: 3
          }
          evaluatedRecurrence: {
            frequency: 'Minute'
            interval: 3
          }
          type: 'Recurrence'
        }
      }
      actions: {
        CleanupSensorItemBatchAttributeMappingsIfMoreThanOneBlob: {
          actions: {
            FilterSensorItemBatchAttributeMappingsOlderThan7Days: {
              runAfter: {}
              type: 'Query'
              inputs: {
                from: '''@body('ListAllSensorJobItembatchAttributeMappings')?['value']'''
                where: '''@less(item()?['LastModified'], subtractFromTime(utcNow(), 7, 'Day'))'''
              }
            }
            For_each_3: {
              foreach: '''@body('FilterSensorItemBatchAttributeMappingsOlderThan7Days')'''
              actions: {
                'Delete_blob_(V2)': {
                  runAfter: {}
                  type: 'ApiConnection'
                  inputs: {
                    headers: {
                      SkipDeleteIfFileNotFoundOnServer: false
                    }
                    host: {
                      connection: {
                        name: '''@parameters('$connections')['azureblob']['connectionId']'''
                      }
                    }
                    method: 'delete'
                    path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccount.name}\'))}/files/@{encodeURIComponent(encodeURIComponent(items(\'For_each_3\')?[\'Path\']))}'
                  }
                }
              }
              runAfter: {
                FilterSensorItemBatchAttributeMappingsOlderThan7Days: [
                  'Succeeded'
                ]
              }
              type: 'Foreach'
            }
          }
          runAfter: {
            ListAllSensorJobItembatchAttributeMappings: [
              'Succeeded'
            ]
          }
          expression: {
            and: [
              {
                greater: [
                  '''@length(body('ListAllSensorJobItembatchAttributeMappings')?['value'])'''
                  1
                ]
              }
            ]
          }
          type: 'If'
        }
        CleanupSensorJobsIfMoreThanOneBlob: {
          actions: {
            FilterSensorJobsBlobsOlderThan7Days: {
              runAfter: {}
              type: 'Query'
              inputs: {
                from: '''@body('ListAllSensorJobsBlobs')?['value']'''
                where: '''@less(item()?['LastModified'], subtractFromTime(utcNow(), 7, 'Day'))'''
              }
            }
            For_each: {
              foreach: '''@body('FilterSensorJobsBlobsOlderThan7Days')'''
              actions: {
                DeleteOldSensorJobsBlob: {
                  runAfter: {}
                  type: 'ApiConnection'
                  inputs: {
                    headers: {
                      SkipDeleteIfFileNotFoundOnServer: false
                    }
                    host: {
                      connection: {
                        name: '''@parameters('$connections')['azureblob']['connectionId']'''
                      }
                    }
                    method: 'delete'
                    path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccount.name}\'))}/files/@{encodeURIComponent(encodeURIComponent(items(\'For_each\')?[\'Path\']))}'
                  }
                }
              }
              runAfter: {
                FilterSensorJobsBlobsOlderThan7Days: [
                  'Succeeded'
                ]
              }
              type: 'Foreach'
            }
          }
          runAfter: {
            ListAllSensorJobsBlobs: [
              'Succeeded'
            ]
          }
          expression: {
            and: [
              {
                greater: [
                  '''@length(body('ListAllSensorJobsBlobs')?['value'])'''
                  1
                ]
              }
            ]
          }
          type: 'If'
        }
        CreateSensorItemBatchAttributeMappingsBlob: {
          runAfter: {
            Parse_JSON: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            body: '''@body('Parse_JSON')?['value']'''
            headers: {
              ReadFileMetadataFromServer: true
            }
            host: {
              connection: {
                name: '''@parameters('$connections')['azureblob']['connectionId']'''
              }
            }
            method: 'post'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccount.name}\'))}/files'
            queries: {
              folderPath: '${storageAccount::blobServices::referenceDataBlobContainer.name}/sensorjobbatchattributes'
              name: '''@{concat('sensorjobitembatchattributemappings', utcNow('yyyy-MM-ddTHH-mm'), '.json')}'''
              queryParametersSingleEncoded: true
            }
          }
          runtimeConfiguration: {
            contentTransfer: {
              transferMode: 'Chunked'
            }
          }
        }
        CreateSensorJobsBlob: {
          runAfter: {
            Parse_JSON_2: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            body: '''@body('Parse_JSON_2')?['value']'''
            headers: {
              ReadFileMetadataFromServer: true
            }
            host: {
              connection: {
                name: '''@parameters('$connections')['azureblob']['connectionId']'''
              }
            }
            method: 'post'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccount.name}\'))}/files'
            queries: {
              folderPath: '${storageAccount::blobServices::referenceDataBlobContainer.name}/sensorjobs'
              name: '''@{concat('sensorjobs', utcNow('yyyy-MM-ddTHH-mm'), '.json')}'''
              queryParametersSingleEncoded: true
            }
          }
          runtimeConfiguration: {
            contentTransfer: {
              transferMode: 'Chunked'
            }
          }
        }
        GetSensorItemBatchAttributeMappings: {
          runAfter: {}
          type: 'Http'
          inputs: {
            authentication: {
              audience: '00000015-0000-0000-c000-000000000000'
              type: 'ManagedServiceIdentity'
              // Microsoft.ERP first-party app, works for all FnO environments.
              identity: sharedLogicAppIdentity.id
            }
            method: 'GET'
            uri: uri(trimmedEnvironmentUrl, '/data/SensorJobItemBatchAttributes')
          }
        }
        GetSensorJobs: {
          runAfter: {}
          type: 'Http'
          inputs: {
            authentication: {
              audience: '00000015-0000-0000-c000-000000000000'
              type: 'ManagedServiceIdentity'
              // Microsoft.ERP first-party app, works for all FnO environments.
              identity: sharedLogicAppIdentity.id
            }
            method: 'GET'
            uri: uri(trimmedEnvironmentUrl, '/data/SensorJobs')
          }
        }
        ListAllSensorJobItembatchAttributeMappings: {
          runAfter: {}
          metadata: {
            'JTJmc2Vuc29yaW50ZWxsaWdlbmNlcmVmZXJlbmNlZGF0YSUyZnNlbnNvcmpvYmJhdGNoYXR0cmlidXRlcyUyZg==': '/${storageAccount::blobServices::referenceDataBlobContainer.name}/sensorjobbatchattributes/'
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '''@parameters('$connections')['azureblob']['connectionId']'''
              }
            }
            method: 'get'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccount.name}\'))}/foldersV2/@{encodeURIComponent(encodeURIComponent(\'/${storageAccount::blobServices::referenceDataBlobContainer.name}/sensorjobbatchattributes\'))}'
            queries: {
              nextPageMarker: ''
              useFlatListing: false
            }
          }
        }
        ListAllSensorJobsBlobs: {
          runAfter: {}
          metadata: {
            'JTJmc2Vuc29yaW50ZWxsaWdlbmNlcmVmZXJlbmNlZGF0YSUyZnNlbnNvcmpvYnMlMmY=': '/${storageAccount::blobServices::referenceDataBlobContainer.name}/sensorjobs/'
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '''@parameters('$connections')['azureblob']['connectionId']'''
              }
            }
            method: 'get'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccount.name}\'))}/foldersV2/@{encodeURIComponent(encodeURIComponent(\'JTJmc2Vuc29yaW50ZWxsaWdlbmNlcmVmZXJlbmNlZGF0YSUyZnNlbnNvcmpvYnMlMmY=\'))}'
            queries: {
              nextPageMarker: ''
              useFlatListing: false
            }
          }
        }
        Parse_JSON: {
          runAfter: {
            GetSensorItemBatchAttributeMappings: [
              'Succeeded'
            ]
          }
          type: 'ParseJson'
          inputs: {
            content: '''@body('GetSensorItemBatchAttributeMappings')'''
            schema: {
              properties: {
                '@@odata.context': {
                  type: 'string'
                }
                value: {
                  type: 'array'
                }
              }
              type: 'object'
            }
          }
        }
        Parse_JSON_2: {
          runAfter: {
            GetSensorJobs: [
              'Succeeded'
            ]
          }
          type: 'ParseJson'
          inputs: {
            content: '''@body('GetSensorJobs')'''
            schema: {
              properties: {
                '@@odata.context': {
                  type: 'string'
                }
                value: {
                  type: 'array'
                }
              }
              type: 'object'
            }
          }
        }
      }
      outputs: {}
    }
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
        'When_Insight_is_added_to_outbound_queue_(peek-lock)': {
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
            path: '/@{encodeURIComponent(encodeURIComponent(\'${asaToDynamicsServiceBus::outboundInsightsQueue.name}\'))}/messages/head/peek'
            queries: {
              queryType: 'Main'
            }
          }
        }
      }
      actions: {
        Parse_Insight: {
          inputs: {
            content: '''@decodeBase64(triggerBody()?['ContentData'])'''
            schema: {
              properties: {
                NotificationRaisedDateTime: {
                  type: 'string'
                }
                Type: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
          runAfter: {}
          type: 'ParseJson'
        }
        Notification_GUID: {
          inputs: {
            variables: [
              {
                name: 'NotificationGUID'
                type: 'string'
                value: '''@triggerBody()?['LockToken']'''
              }
            ]
          }
          runAfter: {
            Parse_Insight: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
        }
        Compose_Notification_object: {
          inputs: {
            Id: '''@{variables('NotificationGUID')}'''
            NotificationRaisedDateTime: '''@{body('Parse_Insight')?['NotificationRaisedDateTime']}'''
            Payload: '''@decodeBase64(triggerBody()?['ContentData'])'''
            Type: '''@{body('Parse_Insight')?['Type']}'''
          }
          runAfter: {
            Notification_GUID: [
              'Succeeded'
            ]
          }
          type: 'Compose'
        }
        Post_Notification: {
          inputs: {
            authentication: {
              audience: '00000015-0000-0000-c000-000000000000'
              identity: sharedLogicAppIdentity.id
              type: 'ManagedServiceIdentity'
            }
            body: '''@outputs('Compose_Notification_object')'''
            headers: {
              'Content-Type': 'application/json'
            }
            method: 'POST'
            uri: uri(trimmedEnvironmentUrl, '/data/OperationsNotifications')
          }
          runAfter: {
            Compose_Notification_object: [
              'Succeeded'
            ]
          }
          type: 'Http'
        }
        Complete_Insight_message_in_queue: {
          inputs: {
            host: {
              connection: {
                name: '''@parameters('$connections')['servicebus']['connectionId']'''
              }
            }
            method: 'delete'
            path: '/@{encodeURIComponent(encodeURIComponent(\'${asaToDynamicsServiceBus::outboundInsightsQueue.name}\'))}/messages/complete'
            queries: {
              lockToken: '''@triggerBody()?['LockToken']'''
              queueType: 'Main'
              sessionId: ''
            }
          }
          runAfter: {
            Post_Notification: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
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

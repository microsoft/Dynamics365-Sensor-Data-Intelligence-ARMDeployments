param name string = ''

@minLength(1)
param location string = ''

param userAssignedIdentityResourceId string = ''

param axEnvironmentUrl string = ''

param storageAccountName string = ''

param storageAccountConnectionId string = ''

param referenceDataBlobContainerName string = ''

resource refDataLogicApp2 'Microsoft.Logic/workflows@2019-05-01' = {
  name: name
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityResourceId}': {}
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
                    path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccountName}\'))}/files/@{encodeURIComponent(encodeURIComponent(items(\'For_each_3\')?[\'Path\']))}'
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
                    path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccountName}\'))}/files/@{encodeURIComponent(encodeURIComponent(items(\'For_each\')?[\'Path\']))}'
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
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccountName}\'))}/files'
            queries: {
              folderPath: '${referenceDataBlobContainerName}/sensorjobbatchattributes'
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
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccountName}\'))}/files'
            queries: {
              folderPath: '${referenceDataBlobContainerName}/sensorjobs'
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
              // Microsoft.ERP first-party app, works for all FnO environments.
              audience: '00000015-0000-0000-c000-000000000000'
              type: 'ManagedServiceIdentity'
              identity: userAssignedIdentityResourceId
            }
            method: 'GET'
            uri: uri(axEnvironmentUrl, '/data/SensorJobItemBatchAttributes')
          }
        }
        GetSensorJobs: {
          runAfter: {}
          type: 'Http'
          inputs: {
            authentication: {
              // Microsoft.ERP first-party app, works for all FnO environments.
              audience: '00000015-0000-0000-c000-000000000000'
              type: 'ManagedServiceIdentity'
              identity: userAssignedIdentityResourceId
            }
            method: 'GET'
            uri: uri(axEnvironmentUrl, '/data/SensorJobs')
          }
        }
        ListAllSensorJobItembatchAttributeMappings: {
          runAfter: {}
          metadata: {
            'JTJmc2Vuc29yaW50ZWxsaWdlbmNlcmVmZXJlbmNlZGF0YSUyZnNlbnNvcmpvYmJhdGNoYXR0cmlidXRlcyUyZg==': '/${referenceDataBlobContainerName}/sensorjobbatchattributes/'
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '''@parameters('$connections')['azureblob']['connectionId']'''
              }
            }
            method: 'get'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccountName}\'))}/foldersV2/@{encodeURIComponent(encodeURIComponent(\'/${referenceDataBlobContainerName}/sensorjobbatchattributes\'))}'
            queries: {
              nextPageMarker: ''
              useFlatListing: false
            }
          }
        }
        ListAllSensorJobsBlobs: {
          runAfter: {}
          metadata: {
            'JTJmc2Vuc29yaW50ZWxsaWdlbmNlcmVmZXJlbmNlZGF0YSUyZnNlbnNvcmpvYnMlMmY=': '/${referenceDataBlobContainerName}/sensorjobs/'
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '''@parameters('$connections')['azureblob']['connectionId']'''
              }
            }
            method: 'get'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccountName}\'))}/foldersV2/@{encodeURIComponent(encodeURIComponent(\'JTJmc2Vuc29yaW50ZWxsaWdlbmNlcmVmZXJlbmNlZGF0YSUyZnNlbnNvcmpvYnMlMmY=\'))}'
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
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
            connectionId: storageAccountConnectionId
            connectionName: 'azureblob'
            connectionProperties: {
              authentication: {
                identity: userAssignedIdentityResourceId
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

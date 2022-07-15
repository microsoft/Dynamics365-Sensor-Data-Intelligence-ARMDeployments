# Extended use <!-- omit in toc -->

While this template can be used as-is, it is not necessarily compliant with your organization's production policies.

High-end scaling, monitoring and VNet isolation are left out of the template to keep baseline costs low and reduce complexity of the template,
such that anyone can read and understand it with ease.

This document provides suggestions on how to fork this template and lift it into compliance if the baseline is not enough.

- [Adding monitoring](#adding-monitoring)
- [Adding VNet isolation](#adding-vnet-isolation)
  - [Stream Analytics jobs isolation](#stream-analytics-jobs-isolation)
  - [Redis Cache isolation](#redis-cache-isolation)
  - [Isolation of other resource types](#isolation-of-other-resource-types)
- [Scaling](#scaling)
  - [Azure Function scaling](#azure-function-scaling)
  - [IoT Hub scaling](#iot-hub-scaling)
  - [Redis Cache scaling](#redis-cache-scaling)
  - [Service Bus scaling](#service-bus-scaling)
  - [Stream Analytics jobs scaling](#stream-analytics-jobs-scaling)

## Adding monitoring

For policy reasons, or to debug, monitoring can be enabled for each of the resources deployed by this template.

Each resource has a blade in the Azure Portal for enabling diagnostics:

![Image showing where to find "Diagnostic settings" under "Monitoring" in the Azure Portal](https://user-images.githubusercontent.com/639843/179007359-12f398d0-1c16-4b0f-88fc-c66242ffebf1.png)

In the "Diagnostic settings" blade, click "+ Add diagnostic setting" and choose which logs and metrics to forward, then select a destination- sending logs to a Log Analytics workspace provides great querying capabilities of the collected logs.

Find more details on logging for each resource type used by this template in the below list:

- Azure Cache for Redis, see: <https://docs.microsoft.com/azure/azure-cache-for-redis/cache-monitor-diagnostic-settings>.
- Azure Function:
  - Application Insights, see: <https://docs.microsoft.com/azure/azure-functions/configure-monitoring>.
  - Diagnostic logging (Azure Monitor), see: <https://docs.microsoft.com/azure/azure-functions/functions-monitor-log-analytics>.
- IoT Hub, see: <https://docs.microsoft.com/azure/iot-hub/monitor-iot-hub>.
- Logic Apps, see: <https://docs.microsoft.com/azure/logic-apps/monitor-logic-apps>.
  - Note that, for security reasons, an IP range of `0.0.0.0-0.0.0.0` is added to the Logic Apps' access control configuration to absolutely restrict access to Logic App run history data. To read this data, insert a range that includes your IP address, then delete the existing catch-all range:

    ![Image showing how to delete IP ranges under "Workflow settings" of a Logic App](https://user-images.githubusercontent.com/639843/179010400-cb1970d6-1412-40a2-8fd8-e3d539ff5638.png)
- Service Bus, see: <https://docs.microsoft.com/azure/service-bus-messaging/monitor-service-bus>.
- Storage Account (blob storage), see: <https://docs.microsoft.com/azure/storage/blobs/monitor-blob-storage>.
- Stream Analytics jobs, see: <https://docs.microsoft.com/azure/stream-analytics/stream-analytics-job-diagnostic-logs>.

## Adding VNet isolation

Organizations with strong enterprise security requirements may want or need VNet isolation for their IoT Hub and other Azure resources.

This section describes how to obtain VNet isolation per template resource type.

> Some resource types require higher pricing tiers or SKUs than what is deployed with this template for VNet functionalities to be available.

### Stream Analytics jobs isolation

Azure Stream Analytics jobs do not support VNet isolation unless they are hosted in a dedicated [Azure Stream Analytics cluster](https://docs.microsoft.com/azure/stream-analytics/cluster-overview). To keep costs significantly down for this sample template, the template does not deploy a cluster.

Since the Stream Analytics jobs are at the center of the Azure-hosted Sensor Data Intelligence architecture, it is mandatory to have them running in a VNet before the IoT Hub, Azure Function, Storage, and Service Bus can have VNet isolation.

To add VNet isolation to your Stream Analytics jobs and cluster, see <https://docs.microsoft.com/azure/stream-analytics/connect-job-to-vnet>.

### Redis Cache isolation

At the time of writing, the following limitations apply:

- VNet isolation is only available on Azure Cache for Redis' Premium tier. This template deploys the Basic tier by default.
- VNet isolation cannot be enabled after the Azure Cache for Redis resource has been created- it needs to be created with a reference to the target VNet.

To add VNet isolation to your Azure Cache for Redis, see <https://docs.microsoft.com/azure/azure-cache-for-redis/cache-how-to-premium-vnet>.

### Isolation of other resource types

Below is a list of URLs to guide VNet enablement for other Azure resources used by this template:

- Azure Function, see: <https://docs.microsoft.com/azure/azure-functions/functions-networking-options>.
- IoT Hub, see: <https://docs.microsoft.com/azure/iot-hub/virtual-network-support>.
- Logic Apps, see: <https://docs.microsoft.com/azure/logic-apps/secure-single-tenant-workflow-virtual-network-private-endpoint>.
- Service Bus, see: <https://docs.microsoft.com/azure/service-bus-messaging/service-bus-service-endpoints>.
- Storage Account, see: <https://docs.microsoft.com/azure/storage/common/storage-network-security>.

## Scaling

Each organizations need for scale is different. This template does not attempt to make any assumptions about the size of organization that will be using it, but instead deploys the minimally viable SKUs such that it can be used for testing and by smaller organizations out of the box, at the lowest cost.

This section describes how to plan and scale the template for your organization's needs.

The Storage Account and Logic Apps resources should not need any scaling considerations as they automatically scale as needed.

### Azure Function scaling

The Azure Function to proxy metrics from Stream Analytics jobs to Redis is deployed with a consumption-based Y1 SKU. This means that you pay per execution, execution time and memory cap. The scale of Azure Functions is not unbounded and this template sets a scale out limit (see `functionAppScaleLimit` in [`main.bicep`](./main.bicep)), to avoid the Function scaling beyond an anticipated upper bound.

Should the Azure Function need to scale out beyond the limits set by this template, reconfigure Dynamic scaling under the "Scale out" section of the Function in Azure Portal.

### IoT Hub scaling

By default, the template deploys an Azure IoT Hub with capacity of 1. With the B1 SKU, that gives you 400,000 messages per day (approximately 5 messages per second), at the time of writing.

If you have more than 5 devices, each emitting a single message every _second_, you will need to scale up.

Or, if you have more than 300 devices, each emitting a single message every _minute_, you will need to scale up.

For more advice on scaling your IoT Hub(s), see: <https://docs.microsoft.com/azure/iot-hub/iot-hub-scaling>.

### Redis Cache scaling

By default, the template deploys an Azure Cache for Redis in the Basic tier's C0.

The Standard tier provides a high-availability SLA and two-node configuration (primary/secondary), with increased costs.

For the purposes of use from the Stream Analytics jobs in this repository a higher tier should not be needed, unless your organization is highly dependent on the IoT metrics shown within Dynamics 365 SCM.

Depending on the number of IoT devices enabled for Sensor Data Intelligence scenarios a need may arise to bump to a higher cache size, which lifts the cache out of shared infrastructure and into a dedicated service, while also increasing the networking performance.

For more advice on scaling the Redis Cache, see: <https://docs.microsoft.com/azure/azure-cache-for-redis/cache-how-to-scale>.

### Service Bus scaling

By default, the template deploys a Service Bus using the Standard tier. This should be enough for most operations, regardless of organization and operation size as the Service Bus will not be invoked as much as, for instance, the IoT Hub and Stream Analytics jobs. Notification events (or, insights) should only be sent to Service Bus in case of a significant event occurring, such as a machine going down or asset counter aggregations (once every 3 hours per sensor).

Should a higher tier Service Bus be needed, a Service Bus can be migrated from Standard to the Premium tier, for more details see: <https://docs.microsoft.com/azure/service-bus-messaging/service-bus-migrate-standard-premium>.

### Stream Analytics jobs scaling

Each Stream Analytics job is deployed with a single (1) streaming unit (SU). A single SU will be enough for development, testing and demoing- and perhaps in some smaller-scale organization operations.

In general, queries in each job can scale up to 6 SUs due to [parallelization in Stream Analytics](https://docs.microsoft.com/azure/stream-analytics/stream-analytics-parallelization#calculate-the-max-streaming-units-for-a-job).

If more than a single SU is needed, in case SU utilization constantly sits above a high (>~75%) utilization, jobs can be scaled manually, see: <https://docs.microsoft.com/azure/stream-analytics/stream-analytics-streaming-unit-consumption>.

Jobs can be auto scaled based on usage using custom auto scale, for more details see: <https://docs.microsoft.com/azure/stream-analytics/stream-analytics-autoscale>.

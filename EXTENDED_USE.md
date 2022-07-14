# Extended use <!-- omit in toc -->

While this template can be used as-is, it is not necessarily compliant with your organization's production policies.

High-end scaling, monitoring and VNet isolation are left out of the template to keep baseline costs low and reduce complexity of the template,
such that anyone can read and understand it with ease.

This document provides suggestions on how to fork this template and lift it into compliance if the baseline is not enough.

- [Adding monitoring](#adding-monitoring)
- [Adding VNet isolation](#adding-vnet-isolation)
  - [Stream Analytics jobs](#stream-analytics-jobs)
  - [Redis Cache](#redis-cache)
  - [Other resource types](#other-resource-types)
- [Scaling](#scaling)
  - [IoT Hub](#iot-hub)

## Adding monitoring


## Adding VNet isolation

Organizations with strong enterprise security requirements may want or need VNet isolation for their IoT Hub and other Azure resources.

This section describes how to obtain VNet isolation per template resource type.

### Stream Analytics jobs

Azure Stream Analytics jobs do not support VNet isolation unless they are hosted in a dedicated [Azure Stream Analytics cluster](https://docs.microsoft.com/azure/stream-analytics/cluster-overview). To keep costs significantly down for this sample template, the template does not deploy a cluster.

Since the Stream Analytics jobs are at the center of the Azure-hosted Sensor Data Intelligence architecture, it is mandatory to have them running in a VNet before the IoT Hub, Azure Function, Storage, and Service Bus can have VNet isolation.

To add VNet isolation to your Stream Analytics jobs and cluster, see <https://docs.microsoft.com/azure/stream-analytics/connect-job-to-vnet>.

### Redis Cache

At the time of writing, the following limitations apply:

- VNet isolation is only available on Azure Cache for Redis' Premium tier. This template deploys the Basic tier by default.
- VNet isolation cannot be enabled after the Azure Cache for Redis resource has been created- it needs to be created with a reference to the target VNet.

To add VNet isolation to your Azure Cache for Redis, see <https://docs.microsoft.com/azure/azure-cache-for-redis/cache-how-to-premium-vnet>.

### Other resource types

Below is a list of URLs to guide VNet enablement for other Azure resources used by this template:

- Azure Function, see: <https://docs.microsoft.com/azure/azure-functions/functions-networking-options>.
- IoT Hub, see: <https://docs.microsoft.com/azure/iot-hub/virtual-network-support>.
- Logic Apps, see: <https://docs.microsoft.com/azure/logic-apps/secure-single-tenant-workflow-virtual-network-private-endpoint>.
- Service Bus, see: <https://docs.microsoft.com/azure/service-bus-messaging/service-bus-service-endpoints>.
- Storage Account, see: <https://docs.microsoft.com/azure/storage/common/storage-network-security>.

## Scaling

Each organizations need for scale is different. This template does not attempt to make any assumptions about the size of organization that will be using it, but instead deploys the minimally viable SKUs such that it can be used for testing and by smaller organizations out of the box, at the lowest cost.

This section describes how to plan and scale the template in your organization.

### IoT Hub

By default, the template deploys an Azure IoT Hub with capacity of 1. With the B1 SKU, that gives you 400,000 messages per day (approximately 5 messages per second), at the time of writing.

If you have more than 5 devices, each emitting a single message every second, you will need to scale up.

For more advice on scaling your IoT Hub(s), see <https://docs.microsoft.com/azure/iot-hub/iot-hub-scaling>.

import { distributedDeviceManager } from "@kit.DistributedServiceKit";

@ObservedV2
class Manager {
  deviceManager: distributedDeviceManager.DeviceManager = distributedDeviceManager.createDeviceManager("top.frankhan.easytier")
}

export default new Manager()
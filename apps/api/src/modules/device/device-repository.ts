export type DevicePlatform = "android" | "ios" | "web" | "unknown";

export interface DeviceRepository {
  register(input: {
    userId: string;
    publicKey: string;
    platform: DevicePlatform;
  }): Promise<{ id: string }>;
  revoke(deviceId: string, userId: string): Promise<void>;
}

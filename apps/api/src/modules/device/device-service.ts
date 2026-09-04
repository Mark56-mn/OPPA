import { createPublicKey } from "node:crypto";
import type { DevicePlatform, DeviceRepository } from "./device-repository.js";

const platforms=new Set<DevicePlatform>(["android","ios","web","unknown"]);

export class DeviceService{
 constructor(private readonly devices:DeviceRepository){}
 async register(userId:string,publicKey:string,platform:string){
  if(!userId||userId.length>128||!publicKey||publicKey.length>4096)throw new Error("DEVICE_INPUT_INVALID");
  let key;
  try{key=createPublicKey(publicKey)}catch{throw new Error("DEVICE_KEY_INVALID")}
  if(key.asymmetricKeyType!=="ec" || key.asymmetricKeyDetails?.namedCurve!=="prime256v1")throw new Error("DEVICE_KEY_INVALID");
  const normalizedPlatform=platforms.has(platform as DevicePlatform)?platform as DevicePlatform:"unknown";
  return this.devices.register({userId,publicKey,platform:normalizedPlatform});
 }
 /** Revokes a device owned by the user. Its sessions die with the active-device checks. */
 async revokeDevice(userId:string,deviceId:string){
  if(!userId||userId.length>128||!deviceId||deviceId.length>128)throw new Error("DEVICE_ID_INVALID");
  const r=await this.devices.revoke(deviceId,userId);
  return r;
 }
}

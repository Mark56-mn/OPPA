export interface ContactRepository {
 list(userId:string):Promise<unknown[]>;
 add(userId:string,contactUserId:string,nickname?:string):Promise<unknown>;
 remove(userId:string,contactUserId:string):Promise<void>;
 block(userId:string,contactUserId:string):Promise<void>;
}

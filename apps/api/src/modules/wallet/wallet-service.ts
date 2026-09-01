import type { WalletRepository, WalletTransaction } from "./wallet-repository.js";
import type { SensitiveAuthorization, AuthorizationProof } from "../security/sensitive-authorization.js";
export class WalletService{
 constructor(private readonly wallets:WalletRepository,private readonly authorization?:SensitiveAuthorization){}
 async getBalance(userId:string){return this.wallets.getOrCreate(userId)}
 async getTransactions(userId:string,limit=50,before?:string){return this.wallets.listTransactions(userId,limit,before)}
 async credit(userId:string,amountMinor:number,reference:string,description?:string|null){return this.wallets.credit(userId,amountMinor,reference,description)}
 async debit(userId:string,amountMinor:number,reference:string,description?:string|null){return this.wallets.debit(userId,amountMinor,reference,description)}
 async authorizeTransfer(userId:string,proof:AuthorizationProof){if(!this.authorization)throw Error("SENSITIVE_AUTH_UNAVAILABLE");return this.authorization.authorize({userId,operation:"wallet_transfer",proof})}
}

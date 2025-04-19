import { Transaction } from "@mysten/sui/transactions";
import { WRAPPER_OBJECT_ID } from "../constants";

export function getWithdrawFeeTx({
    coinType,
    target,
    user,
    fundCapId,
    adminCapId,
    transaction
  }: {
    coinType: string;
    target: string;
    user: string;
    fundCapId?: string;
    adminCapId?: string;
    transaction?: Transaction;
  }): Transaction {
    const tx = transaction ?? new Transaction();
  
    let cap: string | undefined;
    if (fundCapId) cap = fundCapId;
    if (adminCapId) cap = adminCapId;
    if (!cap) throw new Error("Either fundCapId or adminCapId must be provided");
  
    const withdrawnCoin = tx.moveCall({
      target,
      typeArguments: [coinType],
      arguments: [tx.object(cap), tx.object(WRAPPER_OBJECT_ID)],
    });
  
    tx.transferObjects([withdrawnCoin], tx.pure.address(user));
  
    return tx;
  }
import { Transaction } from "@mysten/sui/transactions";
import { WRAPPER_OBJECT_ID } from "../constants";

export function getWithdrawFeeTx({
  coinType,
  target,
  user,
  adminCapId,
  transaction,
}: {
  coinType: string;
  target: string;
  user: string;
  adminCapId: string;
  transaction?: Transaction;
}): Transaction {
  const tx = transaction ?? new Transaction();

  const withdrawnCoin = tx.moveCall({
    target,
    typeArguments: [coinType],
    arguments: [tx.object(WRAPPER_OBJECT_ID), tx.object(adminCapId)],
  });

  tx.transferObjects([withdrawnCoin], tx.pure.address(user));

  return tx;
}

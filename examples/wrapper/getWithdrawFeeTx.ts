import { Transaction } from "@mysten/sui/transactions";
import { WRAPPER_OBJECT_ID } from "../constants";

export function getWithdrawFeeTx({
  coinType,
  target,
  user,
  adminCapId,
  transaction,
  pks,
  weights,
  threshold,
}: {
  coinType: string;
  target: string;
  user: string;
  adminCapId: string;
  transaction?: Transaction;
  pks: number[][];
  weights: number[];
  threshold: number;
}): Transaction {
  const tx = transaction ?? new Transaction();

  const withdrawnCoin = tx.moveCall({
    target,
    typeArguments: [coinType],
    arguments: [
      tx.object(WRAPPER_OBJECT_ID),
      tx.object(adminCapId),
      tx.pure.vector("vector<u8>", pks),
      tx.pure.vector("u8", weights),
      tx.pure.u16(threshold),
    ],
  });

  tx.transferObjects([withdrawnCoin], tx.pure.address(user));

  return tx;
}

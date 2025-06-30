import { Transaction } from "@mysten/sui/transactions";
import { WRAPPER_OBJECT_ID } from "../constants";

export function getWithdrawFeeTx({
  coinType,
  target,
  user,
  fundCapId,
  adminCapId,
  transaction,
  pks,
  weights,
  threshold,
}: {
  coinType: string;
  target: string;
  user: string;
  fundCapId?: string;
  adminCapId?: string;
  transaction?: Transaction;
  pks: number[][];
  weights: number[];
  threshold: number;
}): Transaction {
  const tx = transaction ?? new Transaction();

  let cap: string | undefined;
  if (fundCapId) cap = fundCapId;
  if (adminCapId) cap = adminCapId;
  if (!cap) throw new Error("Either fundCapId or adminCapId must be provided");

  const withdrawnCoin = tx.moveCall({
    target,
    typeArguments: [coinType],
    arguments: [
      tx.object(WRAPPER_OBJECT_ID),
      tx.object(cap),
      tx.pure.vector("vector<u8>", pks),
      tx.pure.vector("u8", weights),
      tx.pure.u16(threshold),
    ],
  });

  tx.transferObjects([withdrawnCoin], tx.pure.address(user));

  return tx;
}

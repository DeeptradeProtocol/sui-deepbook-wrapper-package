import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider, user } from "../common";
import { FUND_CAP_OBJECT_ID, NS_COIN_TYPE, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";

// yarn ts-node examples/wrapper/withdraw-coverage-fee.ts > withdraw-coverage-fee.log 2>&1
(async () => {
  const tx = await getWithdrawFeeTx({
    coinType: NS_COIN_TYPE,
    target: `${WRAPPER_PACKAGE_ID}::wrapper::withdraw_deep_reserves_coverage_fee`,
    user,
    fundCapId: FUND_CAP_OBJECT_ID,
  });

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log(res);
})();

export async function getWithdrawFeeTx({
  coinType,
  target,
  user,
  fundCapId,
  adminCapId,
}: {
  coinType: string;
  target: string;
  user: string;
  fundCapId?: string;
  adminCapId?: string;
}): Promise<Transaction> {
  const tx = new Transaction();

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

import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider, user } from "../common";
import { ADMIN_CAP_OBJECT_ID, DEEP_DECIMALS, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";

const WITHDRAW_AMOUNT = 1; // 1 DEEP

// yarn ts-node examples/wrapper/withdraw-deep-reserves.ts > withdraw-deep-reserves.log 2>&1
(async () => {
  const tx = new Transaction();

  const rawAmount = WITHDRAW_AMOUNT * 10 ** DEEP_DECIMALS;

  const withdrawnCoin = tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::withdraw_deep_reserves`,
    arguments: [tx.object(ADMIN_CAP_OBJECT_ID), tx.object(WRAPPER_OBJECT_ID), tx.pure.u64(rawAmount)],
  });

  tx.transferObjects([withdrawnCoin], tx.pure.address(user));

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log(res);
})();

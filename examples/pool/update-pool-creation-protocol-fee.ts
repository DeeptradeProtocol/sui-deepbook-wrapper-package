import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider, user } from "../common";
import { ADMIN_CAP_OBJECT_ID, POOL_CREATION_CONFIG_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";

// Set this value to the amount you want to set the new fee to
const NEW_FEE = 200 * 1_000_000; // 200 DEEP

// yarn ts-node examples/pool/update-pool-creation-protocol-fee.ts
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::pool::update_pool_creation_protocol_fee`,
    arguments: [tx.object(POOL_CREATION_CONFIG_OBJECT_ID), tx.object(ADMIN_CAP_OBJECT_ID), tx.pure.u64(NEW_FEE)],
  });

  // const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });
  const res = await provider.devInspectTransactionBlock({ transactionBlock: tx, sender: user });

  console.log(res);
})();

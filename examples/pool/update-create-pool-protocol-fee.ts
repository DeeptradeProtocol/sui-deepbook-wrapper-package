import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider, user } from "../common";
import { ADMIN_CAP_OBJECT_ID, CREATE_POOL_CONFIG_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";

// Set this value to the amount you want to set the new fee to
const NEW_FEE = 200 * 1_000_000; // 200 DEEP

// yarn ts-node examples/pool/update-create-pool-protocol-fee.ts
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::pool::update_create_pool_protocol_fee`,
    arguments: [tx.object(ADMIN_CAP_OBJECT_ID), tx.object(CREATE_POOL_CONFIG_OBJECT_ID), tx.pure.u64(NEW_FEE)],
  });

  // const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });
  const res = await provider.devInspectTransactionBlock({ transactionBlock: tx, sender: user });

  console.log(res);
})();

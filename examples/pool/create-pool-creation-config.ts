import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider, user } from "../common";
import { ADMIN_CAP_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";

// yarn ts-node examples/pool/create-pool-creation-config.ts
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::pool::create_pool_creation_config`,
    arguments: [tx.object(ADMIN_CAP_OBJECT_ID)],
  });

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });
  // const res = await provider.devInspectTransactionBlock({ transactionBlock: tx, sender: user });

  console.log(res);
})();

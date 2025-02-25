import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider } from "../common";
import { ADMIN_CAP_OBJECT_ID, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";

// yarn ts-node examples/wrapper/create-fund-cap.ts > create-fund-cap.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::create_fund_cap`,
    arguments: [tx.object(ADMIN_CAP_OBJECT_ID), tx.object(WRAPPER_OBJECT_ID)],
  });

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log(res);
})();

import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider, user } from "../common";
import { ADMIN_CAP_OBJECT_ID, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";

// yarn ts-node examples/wrapper/create-fund-cap.ts > create-fund-cap.log 2>&1
(async () => {
  const tx = new Transaction();

  const fundCap = tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::create_fund_cap_v2`,
    arguments: [tx.object(WRAPPER_OBJECT_ID), tx.object(ADMIN_CAP_OBJECT_ID)],
  });

  tx.transferObjects([fundCap], tx.pure.address(user));

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log(res);
})();

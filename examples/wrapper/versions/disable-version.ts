import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider } from "../../common";
import { ADMIN_CAP_OBJECT_ID, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../../constants";

// Set the version to disable here
const VERSION = 1;

// Usage: yarn ts-node examples/wrapper/versions/disable-version.ts > disable-version.log 2>&1
(async () => {
  console.log(`Disabling version ${VERSION}...`);

  const tx = new Transaction();

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::disable_version`,
    arguments: [tx.object(WRAPPER_OBJECT_ID), tx.object(ADMIN_CAP_OBJECT_ID), tx.pure.u16(VERSION)],
  });

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log(res);
})();

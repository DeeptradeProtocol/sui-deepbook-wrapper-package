import { Transaction } from "@mysten/sui/transactions";
import { provider } from "../../common";
import { ADMIN_CAP_OBJECT_ID, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../../constants";
import { buildAndLogMultisigTransaction, MULTISIG_CONFIG } from "../../multisig";

// Set the version to enable here
const VERSION = 2;

// Usage: yarn ts-node examples/wrapper/versions/enable-version.ts > enable-version.log 2>&1
(async () => {
  const tx = new Transaction();


  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::enable_version`,
    arguments: [
      tx.object(WRAPPER_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u16(VERSION),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.publicKeysSuiBytes),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
    ],
  });

  console.warn(`Building transaction to enable version ${VERSION}`);

  await buildAndLogMultisigTransaction(tx);
})();

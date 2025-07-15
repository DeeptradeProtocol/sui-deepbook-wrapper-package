import { Transaction } from "@mysten/sui/transactions";
import { provider } from "../../common";
import { ADMIN_CAP_OBJECT_ID, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../../constants";
import { MULTISIG_CONFIG } from "../../multisig";

// Set the version to disable here
const VERSION = 1;


// Usage: yarn ts-node examples/wrapper/versions/disable-version.ts > disable-version.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::disable_version`,
    arguments: [
      tx.object(WRAPPER_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u16(VERSION),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.pks),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
    ],
  });

  console.warn(`Building transaction to disable version ${VERSION}`);

  // Set sender for the transaction
  tx.setSender(MULTISIG_CONFIG.address);

  // Build transaction bytes for signing
  const transactionBytes = await tx.build({ client: provider });
  const base64TxBytes = Buffer.from(transactionBytes).toString("base64");
  console.log("Transaction bytes (base64):", base64TxBytes);

  // Dry run to verify transaction is valid
  const dryRunResult = await provider.dryRunTransactionBlock({
    transactionBlock: transactionBytes,
  });

  console.log("Transaction validation:", dryRunResult.effects.status);

  if (dryRunResult.effects.status.status === "success") {
    console.log("✅ Transaction is valid");
    console.log("\n📋 Next steps:");
    console.log("1. Share these transaction bytes with signers");
    console.log("2. Collect signatures from required signers");
    console.log("3. Combine signatures using multisig tools");
    console.log("4. Execute the signed transaction");
  } else {
    console.log("❌ Transaction validation failed:", dryRunResult.effects.status);
  }
})();

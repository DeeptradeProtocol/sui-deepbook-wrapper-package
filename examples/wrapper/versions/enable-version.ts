import { Transaction } from "@mysten/sui/transactions";
import { provider } from "../../common";
import { ADMIN_CAP_OBJECT_ID, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../../constants";
import { base64ToBytes } from "../../utils";
import { miltisigSignersBase64Pubkeys, weights, threshold, multisigAddress } from "../../multisig";

// Set the version to enable here
const VERSION = 2;

// Usage: yarn ts-node examples/wrapper/versions/enable-version.ts > enable-version.log 2>&1
(async () => {
  const tx = new Transaction();

  const pks = miltisigSignersBase64Pubkeys.map((pubkey) => base64ToBytes(pubkey));

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::enable_version`,
    arguments: [
      tx.object(WRAPPER_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u16(VERSION),
      tx.pure.vector("vector<u8>", pks),
      tx.pure.vector("u8", weights),
      tx.pure.u16(threshold),
    ],
  });

  console.warn(`Building transaction to enable version ${VERSION}`);

  // Set sender for the transaction
  tx.setSender(multisigAddress);

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

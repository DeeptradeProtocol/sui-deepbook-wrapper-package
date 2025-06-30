import { Transaction } from "@mysten/sui/transactions";
import { provider } from "../common";
import { ADMIN_CAP_OBJECT_ID, POOL_CREATION_CONFIG_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";
import { base64ToBytes } from "../utils";

// Set this value to the amount you want to set the new fee to
const NEW_FEE = 200 * 1_000_000; // 200 DEEP

// Paste your multisig signers base64! pubkeys, weights, threshold and hex multisig address here
const miltisigSignersBase64Pubkeys: string[] = [];
const weights: number[] = [];
const threshold = 0;
const multisigAddress = "";

// yarn ts-node examples/pool/update-create-pool-protocol-fee.ts
(async () => {
  console.warn(`Building transaction to update pool creation protocol fee to ${NEW_FEE / 1_000_000} DEEP`);

  const pks = miltisigSignersBase64Pubkeys.map((pubkey) => base64ToBytes(pubkey));

  const tx = new Transaction();

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::pool::update_create_pool_protocol_fee_v2`,
    arguments: [
      tx.object(POOL_CREATION_CONFIG_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u64(NEW_FEE),
      tx.pure.vector("vector<u8>", pks),
      tx.pure.vector("u8", weights),
      tx.pure.u16(threshold),
    ],
  });

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

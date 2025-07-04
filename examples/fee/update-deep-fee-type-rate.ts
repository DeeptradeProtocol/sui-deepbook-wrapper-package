import { Transaction } from "@mysten/sui/transactions";
import { provider } from "../common";
import { ADMIN_CAP_OBJECT_ID, TRADING_FEE_CONFIG_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";
import { base64ToBytes, percentageInBillionths } from "../utils";

// Set this value to the percentage you want to set the new fee rate to
const NEW_FEE = 5; // 5%

// Paste your multisig signers base64! pubkeys, weights, threshold and hex multisig address here
const miltisigSignersBase64Pubkeys: string[] = [];
const weights: number[] = [];
const threshold = 0;
const multisigAddress = "";

// yarn ts-node examples/fee/update-deep-fee-type-rate.ts
(async () => {
  console.warn(`Building transaction to update deep fee type rate to ${NEW_FEE}%`);

  const pks = miltisigSignersBase64Pubkeys.map((pubkey) => base64ToBytes(pubkey));

  const tx = new Transaction();

  const newFeeInBillionths = percentageInBillionths(NEW_FEE);

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::fee::update_deep_fee_type_rate`,
    arguments: [
      tx.object(TRADING_FEE_CONFIG_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u64(newFeeInBillionths),
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

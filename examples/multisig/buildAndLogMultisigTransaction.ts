import { Transaction } from "@mysten/sui/transactions";
import { toBase64 } from "@mysten/sui/utils";
import { provider } from "../common";
import { MULTISIG_CONFIG } from "./multisig";

/**
 * Handles the boilerplate of building, dry running, and logging a multisig transaction.
 * @param tx - The transaction block to process.
 */
export async function buildAndLogMultisigTransaction(tx: Transaction): Promise<void> {
  tx.setSender(MULTISIG_CONFIG.address);

  const transactionBytes = await tx.build({ client: provider });
  const base64TxBytes = toBase64(transactionBytes);
  console.log("\nTransaction bytes (base64):", base64TxBytes);

  console.log("\n🔍 Performing dry run to validate transaction...");
  const dryRunResult = await provider.dryRunTransactionBlock({
    transactionBlock: transactionBytes,
  });

  console.log("Transaction validation:", dryRunResult.effects.status.status);

  if (dryRunResult.effects.status.status === "success") {
    console.log("✅ Transaction is valid");
    console.log("\n📋 Next steps:");
    console.log("1. Share these transaction bytes with the other signers.");
    console.log("2. Each signer must sign the transaction bytes using `sui keytool sign`.");
    console.log("3. Combine the signatures using `sui keytool multi-sig-combine-partial-sig`.");
    console.log("4. Execute the combined transaction using `sui client execute-signed-tx`.");
  } else {
    console.log("❌ Transaction validation failed:", dryRunResult.effects.status.error);
  }
}

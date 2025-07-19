import { provider } from "../common";
import { ADMIN_CAP_OBJECT_ID, NS_COIN_TYPE, WRAPPER_PACKAGE_ID } from "../constants";
import { MULTISIG_CONFIG } from "../multisig";
import { getWithdrawFeeTx } from "./getWithdrawFeeTx";

// yarn ts-node examples/wrapper/admin-withdraw-coverage-fee.ts > admin-withdraw-coverage-fee.log 2>&1
(async () => {
  console.warn(`Building transaction to withdraw coverage fees for ${NS_COIN_TYPE}`);

  const tx = getWithdrawFeeTx({
    coinType: NS_COIN_TYPE,
    target: `${WRAPPER_PACKAGE_ID}::wrapper::withdraw_deep_reserves_coverage_fee`,
    user: MULTISIG_CONFIG.address,
    adminCapId: ADMIN_CAP_OBJECT_ID,
    pks: MULTISIG_CONFIG.publicKeysSuiBytes,
    weights: MULTISIG_CONFIG.weights,
    threshold: MULTISIG_CONFIG.threshold,
  });

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

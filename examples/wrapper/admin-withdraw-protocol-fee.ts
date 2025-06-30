import { provider } from "../common";
import { ADMIN_CAP_OBJECT_ID, DEEP_COIN_TYPE, SUI_COIN_TYPE, WRAPPER_PACKAGE_ID } from "../constants";
import { base64ToBytes } from "../utils";
import { getWithdrawFeeTx } from "./getWithdrawFeeTx";

// Paste your multisig signers base64! pubkeys, weights, threshold and multisig address here
const miltisigSignersBase64Pubkeys: string[] = [];
const weights: number[] = [];
const threshold = 0;
const multisigAddress = "";

// yarn ts-node examples/wrapper/admin-withdraw-protocol-fee.ts > admin-withdraw-protocol-fee.log 2>&1
(async () => {
  console.warn(`Building transaction to withdraw protocol fees for SUI and DEEP`);

  const pks = miltisigSignersBase64Pubkeys.map((pubkey) => base64ToBytes(pubkey));

  // Withdraw SUI protocol fee
  const tx = getWithdrawFeeTx({
    coinType: SUI_COIN_TYPE,
    target: `${WRAPPER_PACKAGE_ID}::wrapper::admin_withdraw_protocol_fee_v2`,
    user: multisigAddress,
    adminCapId: ADMIN_CAP_OBJECT_ID,
    pks,
    weights,
    threshold,
  });

  // Withdraw DEEP protocol fee (pool creation fee)
  getWithdrawFeeTx({
    coinType: DEEP_COIN_TYPE,
    target: `${WRAPPER_PACKAGE_ID}::wrapper::admin_withdraw_protocol_fee_v2`,
    user: multisigAddress,
    adminCapId: ADMIN_CAP_OBJECT_ID,
    transaction: tx,
    pks,
    weights,
    threshold,
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

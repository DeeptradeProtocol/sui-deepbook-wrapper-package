import { Transaction } from "@mysten/sui/transactions";
import { provider } from "../common";
import { ADMIN_CAP_OBJECT_ID, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";
import { getDeepReservesBalance } from "./utils/getDeepReservesBalance";
import { MULTISIG_CONFIG } from "../multisig";

// yarn ts-node examples/wrapper/withdraw-all-deep-reserves.ts > withdraw-all-deep-reserves.log 2>&1
(async () => {
  const tx = new Transaction();

  const { deepReservesRaw: amountToWithdraw, deepReserves: amountToWithdrawFormatted } = await getDeepReservesBalance();


  const withdrawnCoin = tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::withdraw_deep_reserves`,
    arguments: [
      tx.object(WRAPPER_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u64(amountToWithdraw),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.publicKeysSuiBytes),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
    ],
  });

  tx.transferObjects([withdrawnCoin], tx.pure.address(MULTISIG_CONFIG.address));

  console.warn(`Building transaction to withdraw ${amountToWithdrawFormatted} DEEP`);

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

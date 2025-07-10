import { Transaction } from "@mysten/sui/transactions";
import { provider } from "../../common";
import { ADMIN_CAP_OBJECT_ID, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../../constants";
import { base64ToBytes } from "../../utils";
import { getDeepReservesBalance } from "../../wrapper/utils/getDeepReservesBalance";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";

// Paste the ticket object id from the ticket creation step here
const TICKET_OBJECT_ID = "";

// Set the amount to withdraw (or use 0 to withdraw all available reserves)
const AMOUNT_TO_WITHDRAW = 0; // 0 means withdraw all

// Paste your multisig signers base64! pubkeys, weights, threshold and hex multisig address here
const multisigSignersBase64Pubkeys: string[] = [];
const weights: number[] = [];
const threshold = 0;
const multisigAddress = "";

// yarn ts-node examples/timelock-examples/execute-withdraw-deep-reserves.ts > execute-withdraw-deep-reserves.log 2>&1
(async () => {
  if (!TICKET_OBJECT_ID) {
    console.error("❌ Please set TICKET_OBJECT_ID from the ticket creation step");
    process.exit(1);
  }

  const { deepReservesRaw: availableAmount, deepReserves: availableAmountFormatted } = await getDeepReservesBalance();
  const amountToWithdraw = AMOUNT_TO_WITHDRAW || availableAmount;
  const amountToWithdrawFormatted = Number(amountToWithdraw) / 1_000_000;

  console.warn(`Building transaction to withdraw ${amountToWithdrawFormatted} DEEP using ticket ${TICKET_OBJECT_ID}`);
  console.log(`Available reserves: ${availableAmountFormatted} DEEP`);

  const pks = multisigSignersBase64Pubkeys.map((pubkey) => base64ToBytes(pubkey));

  const tx = new Transaction();

  const withdrawnCoin = tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::withdraw_deep_reserves`,
    arguments: [
      tx.object(WRAPPER_OBJECT_ID),
      tx.object(TICKET_OBJECT_ID), // The ticket created in step 1
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u64(amountToWithdraw),
      tx.pure.vector("vector<u8>", pks),
      tx.pure.vector("u8", weights),
      tx.pure.u16(threshold),
      tx.object(SUI_CLOCK_OBJECT_ID),
    ],
  });

  tx.transferObjects([withdrawnCoin], tx.pure.address(multisigAddress));

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
    console.log("\n⚠️ Important notes:");
    console.log("- This will consume the ticket (it can only be used once)");
    console.log("- Make sure at least 24 hours have passed since ticket creation");
    console.log("- The ticket expires 48 hours after creation");
  } else {
    console.log("❌ Transaction validation failed:", dryRunResult.effects.status);
    if (dryRunResult.effects.status.error) {
      console.log("Error details:", dryRunResult.effects.status.error);
    }
  }
})();

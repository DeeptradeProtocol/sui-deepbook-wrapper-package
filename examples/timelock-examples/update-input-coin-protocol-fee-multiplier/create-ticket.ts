import { provider } from "../../common";
import { ADMIN_CAP_OBJECT_ID } from "../../constants";
import { base64ToBytes } from "../../utils";
import { createTicketTx, TicketType } from "../utils/createTicketTx";

// Paste your multisig signers base64! pubkeys, weights, threshold and hex multisig address here
const multisigSignersBase64Pubkeys: string[] = [];
const weights: number[] = [];
const threshold = 0;
const multisigAddress = "";

// yarn ts-node examples/timelock-examples/update-input-coin-protocol-fee-multiplier/create-ticket.ts > create-ticket.log 2>&1
(async () => {
  console.warn("Building transaction to create an update input coin protocol fee multiplier ticket (24h timelock)");

  if (!multisigSignersBase64Pubkeys.length) {
    console.error("❌ Please configure multisig parameters before running this example");
    process.exit(1);
  }

  const pks = multisigSignersBase64Pubkeys.map((pubkey) => base64ToBytes(pubkey));

  const { tx, ticket } = createTicketTx({
    ticketType: TicketType.UpdateInputCoinProtocolFeeMultiplier,
    adminCapId: ADMIN_CAP_OBJECT_ID,
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
    console.log("5. Note the ticket object ID from the transaction result");
    console.log("\n⏰ Timeline:");
    console.log("- Ticket becomes usable: 24 hours after creation");
    console.log("- Ticket expires: 48 hours after creation");
    console.log("- Purpose: Update the input coin protocol fee multiplier");
  } else {
    console.log("❌ Transaction validation failed:", dryRunResult.effects.status);
    if (dryRunResult.effects.status.error) {
      console.log("Error details:", dryRunResult.effects.status.error);
    }
  }
})().catch(console.error);

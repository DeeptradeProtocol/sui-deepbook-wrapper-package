import { provider } from "../../common";
import { ADMIN_CAP_OBJECT_ID } from "../../constants";
import { base64ToBytes } from "../../utils";
import { createTicketTx, TicketType } from "../utils/createTicketTx";

// Paste your multisig signers base64! pubkeys, weights, threshold and hex multisig address here
const multisigSignersBase64Pubkeys: string[] = [];
const weights: number[] = [];
const threshold = 0;
const multisigAddress = "";

// yarn ts-node examples/timelock-examples/create-withdraw-deep-reserves-ticket.ts > create-withdraw-deep-reserves-ticket.log 2>&1
(async () => {
  console.warn("Building transaction to create a withdraw DEEP reserves ticket (24h timelock)");

  const pks = multisigSignersBase64Pubkeys.map((pubkey) => base64ToBytes(pubkey));

  const { tx, ticket } = createTicketTx({
    ticketType: TicketType.WithdrawDeepReserves,
    adminCapId: ADMIN_CAP_OBJECT_ID,
    pks,
    weights,
    threshold,
  });

  // Transfer the ticket to the multisig address for later use
  tx.transferObjects([ticket], tx.pure.address(multisigAddress));

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
    console.log("5. Wait 24 hours for the timelock period");
    console.log("6. Use the ticket ID from the execution to withdraw reserves");
    console.log("\n⏰ Timelock Info:");
    console.log("- Delay period: 24 hours after ticket creation");
    console.log("- Active period: 24 hours after delay ends");
    console.log("- Total window: 48 hours from creation");
  } else {
    console.log("❌ Transaction validation failed:", dryRunResult.effects.status);
  }
})();

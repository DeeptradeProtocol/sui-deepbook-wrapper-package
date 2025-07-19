import { ADMIN_CAP_OBJECT_ID } from "../../constants";
import { buildAndLogMultisigTransaction } from "../../multisig/buildAndLogMultisigTransaction";
import { MULTISIG_CONFIG } from "../../multisig/multisig";
import { createTicketTx, TicketType } from "../utils/createTicketTx";

// yarn ts-node examples/timelock-examples/update-default-pool-fees/create-ticket.ts > create-ticket.log 2>&1
async () => {
  console.warn("Building transaction to create an update default pool fees ticket");

  const { tx, ticket } = createTicketTx({
    ticketType: TicketType.UpdateDefaultFees,
    adminCapId: ADMIN_CAP_OBJECT_ID,
    pks: MULTISIG_CONFIG.publicKeysSuiBytes,
    weights: MULTISIG_CONFIG.weights,
    threshold: MULTISIG_CONFIG.threshold,
  });

  await buildAndLogMultisigTransaction(tx);
};

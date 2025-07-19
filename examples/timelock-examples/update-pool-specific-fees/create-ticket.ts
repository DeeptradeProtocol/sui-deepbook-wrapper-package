import { ADMIN_CAP_OBJECT_ID } from "../../constants";
import { createTicketTx, TicketType } from "../utils/createTicketTx";
import { MULTISIG_CONFIG } from "../../multisig/multisig";
import { buildAndLogMultisigTransaction } from "../../multisig/buildAndLogMultisigTransaction";

// yarn ts-node examples/timelock-examples/update-pool-specific-fees/create-ticket.ts > create-ticket.log 2>&1
(async () => {
  console.warn("Building transaction to create an update pool specific fees ticket");

  const { tx, ticket } = createTicketTx({
    ticketType: TicketType.UpdatePoolSpecificFees,
    adminCapId: ADMIN_CAP_OBJECT_ID,
    pks: MULTISIG_CONFIG.publicKeysSuiBytes,
    weights: MULTISIG_CONFIG.weights,
    threshold: MULTISIG_CONFIG.threshold,
  });

  await buildAndLogMultisigTransaction(tx);
};

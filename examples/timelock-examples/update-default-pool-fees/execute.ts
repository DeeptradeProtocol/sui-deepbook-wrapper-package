import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, TRADING_FEE_CONFIG_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../../constants";
import { percentageInBillionths } from "../../utils";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";
import { MULTISIG_CONFIG } from "../../multisig/multisig";
import { buildAndLogMultisigTransaction } from "../../multisig/buildAndLogMultisigTransaction";

// Paste the ticket object id from the ticket creation step here
const TICKET_OBJECT_ID = "";

// Set this value to the percentage you want to set the new fee rate to
const NEW_FEE = 5; // 5%

// yarn ts-node examples/timelock-examples/update-default-pool-fees/execute.ts > execute.log 2>&1
async () => {
  if (!TICKET_OBJECT_ID) {
    console.error("❌ Please set TICKET_OBJECT_ID from the ticket creation step");
    process.exit(1);
  }

  if (!TRADING_FEE_CONFIG_OBJECT_ID) {
    console.error("❌ Please set TRADING_FEE_CONFIG_OBJECT_ID in constants.ts");
    process.exit(1);
  }

  console.warn(`Building transaction to update default pool fees to ${NEW_FEE}% using ticket ${TICKET_OBJECT_ID}`);

  const tx = new Transaction();
  const newFeeInBillionths = percentageInBillionths(NEW_FEE);

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::fee::update_default_fees`,
    arguments: [
      tx.object(TRADING_FEE_CONFIG_OBJECT_ID),
      tx.object(TICKET_OBJECT_ID), // The ticket created in step 1
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u64(newFeeInBillionths),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.publicKeysSuiBytes),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
      tx.object(SUI_CLOCK_OBJECT_ID),
    ],
  });

  await buildAndLogMultisigTransaction(tx);
};

import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, DEEP_DECIMALS, POOL_CREATION_CONFIG_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";

// Set this value to the amount you want to set the new fee to
const NEW_FEE = 200 * 10 ** DEEP_DECIMALS; // 200 DEEP

// yarn ts-node examples/pool/update-pool-creation-protocol-fee.ts
(async () => {
  console.warn(`Building transaction to update pool creation protocol fee to ${NEW_FEE / 10 ** DEEP_DECIMALS} DEEP`);

  const tx = new Transaction();

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::pool::update_pool_creation_protocol_fee`,
    arguments: [
      tx.object(POOL_CREATION_CONFIG_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u64(NEW_FEE),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.publicKeysSuiBytes),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
    ],
  });

  await buildAndLogMultisigTransaction(tx);
})();

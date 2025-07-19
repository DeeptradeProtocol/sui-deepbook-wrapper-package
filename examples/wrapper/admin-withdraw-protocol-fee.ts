import { ADMIN_CAP_OBJECT_ID, DEEP_COIN_TYPE, SUI_COIN_TYPE, WRAPPER_PACKAGE_ID } from "../constants";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { getWithdrawFeeTx } from "./getWithdrawFeeTx";

// yarn ts-node examples/wrapper/admin-withdraw-protocol-fee.ts > admin-withdraw-protocol-fee.log 2>&1
(async () => {
  console.warn(`Building transaction to withdraw protocol fees for SUI and DEEP`);

  // Withdraw SUI protocol fee
  const tx = getWithdrawFeeTx({
    coinType: SUI_COIN_TYPE,
    target: `${WRAPPER_PACKAGE_ID}::wrapper::withdraw_protocol_fee`,
    user: MULTISIG_CONFIG.address,
    adminCapId: ADMIN_CAP_OBJECT_ID,
    pks: MULTISIG_CONFIG.publicKeysSuiBytes,
    weights: MULTISIG_CONFIG.weights,
    threshold: MULTISIG_CONFIG.threshold,
  });

  // Withdraw DEEP protocol fee (pool creation fee)
  getWithdrawFeeTx({
    coinType: DEEP_COIN_TYPE,
    target: `${WRAPPER_PACKAGE_ID}::wrapper::withdraw_protocol_fee`,
    user: MULTISIG_CONFIG.address,
    adminCapId: ADMIN_CAP_OBJECT_ID,
    transaction: tx,
    pks: MULTISIG_CONFIG.publicKeysSuiBytes,
    weights: MULTISIG_CONFIG.weights,
    threshold: MULTISIG_CONFIG.threshold,
  });

  await buildAndLogMultisigTransaction(tx);

})();

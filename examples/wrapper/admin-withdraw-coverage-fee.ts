import { ADMIN_CAP_OBJECT_ID, NS_COIN_TYPE, WRAPPER_PACKAGE_ID } from "../constants";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { getWithdrawFeeTx } from "./getWithdrawFeeTx";

// yarn ts-node examples/wrapper/admin-withdraw-coverage-fee.ts > admin-withdraw-coverage-fee.log 2>&1
(async () => {
  console.warn(`Building transaction to withdraw coverage fees for ${NS_COIN_TYPE}`);

  const tx = getWithdrawFeeTx({
    coinType: NS_COIN_TYPE,
    target: `${WRAPPER_PACKAGE_ID}::wrapper::withdraw_deep_reserves_coverage_fee`,
    user: MULTISIG_CONFIG.address,
    adminCapId: ADMIN_CAP_OBJECT_ID,
    pks: MULTISIG_CONFIG.publicKeysSuiBytes,
    weights: MULTISIG_CONFIG.weights,
    threshold: MULTISIG_CONFIG.threshold,
  });

  await buildAndLogMultisigTransaction(tx);
})();

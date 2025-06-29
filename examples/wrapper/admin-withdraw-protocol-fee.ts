import { keypair, provider, user } from "../common";
import { ADMIN_CAP_OBJECT_ID, DEEP_COIN_TYPE, SUI_COIN_TYPE, WRAPPER_PACKAGE_ID } from "../constants";
import { getWithdrawFeeTx } from "./getWithdrawFeeTx";

// yarn ts-node examples/wrapper/admin-withdraw-protocol-fee.ts > admin-withdraw-protocol-fee.log 2>&1
(async () => {
  // Withdraw SUI protocol fee
  const tx = getWithdrawFeeTx({
    coinType: SUI_COIN_TYPE,
    target: `${WRAPPER_PACKAGE_ID}::wrapper::admin_withdraw_protocol_fee_v2`,
    user,
    adminCapId: ADMIN_CAP_OBJECT_ID,
  });

  // Withdraw DEEP protocol fee (pool creation fee)
  getWithdrawFeeTx({
    coinType: DEEP_COIN_TYPE,
    target: `${WRAPPER_PACKAGE_ID}::wrapper::admin_withdraw_protocol_fee_v2`,
    user,
    adminCapId: ADMIN_CAP_OBJECT_ID,
    transaction: tx,
  });

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log(res);
})();

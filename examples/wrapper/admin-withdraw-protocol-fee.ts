import { keypair, provider, user } from "../common";
import { ADMIN_CAP_OBJECT_ID, SUI_COIN_TYPE, WRAPPER_PACKAGE_ID } from "../constants";
import { getWithdrawFeeTx } from "./getWithdrawFeeTx";

// yarn ts-node examples/wrapper/admin-withdraw-protocol-fee.ts > admin-withdraw-protocol-fee.log 2>&1
(async () => {
  const tx = getWithdrawFeeTx({
    coinType: SUI_COIN_TYPE,
    target: `${WRAPPER_PACKAGE_ID}::wrapper::admin_withdraw_protocol_fee`,
    user,
    adminCapId: ADMIN_CAP_OBJECT_ID,
  });

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log(res);
})();

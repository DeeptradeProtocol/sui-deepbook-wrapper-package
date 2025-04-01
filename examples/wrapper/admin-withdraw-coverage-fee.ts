import { keypair, provider, user } from "../common";
import { ADMIN_CAP_OBJECT_ID, NS_COIN_TYPE, WRAPPER_PACKAGE_ID } from "../constants";
import { getWithdrawFeeTx } from "./withdraw-coverage-fee";

// yarn ts-node examples/wrapper/admin-withdraw-coverage-fee.ts > admin-withdraw-coverage-fee.log 2>&1
(async () => {
  const tx = await getWithdrawFeeTx({
    coinType: NS_COIN_TYPE,
    target: `${WRAPPER_PACKAGE_ID}::wrapper::admin_withdraw_deep_reserves_coverage_fee`,
    user,
    adminCapId: ADMIN_CAP_OBJECT_ID,
  });

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log(res);
})();

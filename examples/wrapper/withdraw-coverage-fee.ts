import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider, user } from "../common";
import { FUND_CAP_OBJECT_ID, NS_COIN_TYPE, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";
import { getWithdrawFeeTx } from "./getWithdrawFeeTx";

// yarn ts-node examples/wrapper/withdraw-coverage-fee.ts > withdraw-coverage-fee.log 2>&1
(async () => {
  const tx = getWithdrawFeeTx({
    coinType: NS_COIN_TYPE,
    target: `${WRAPPER_PACKAGE_ID}::wrapper::withdraw_deep_reserves_coverage_fee`,
    user,
    fundCapId: FUND_CAP_OBJECT_ID,
  });

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log(res);
})();



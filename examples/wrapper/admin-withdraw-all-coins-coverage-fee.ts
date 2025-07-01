import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider, user } from "../common";
import { ADMIN_CAP_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";
import { getWithdrawFeeTx } from "./getWithdrawFeeTx";
import { getWrapperBags } from "./utils/getWrapperBags";
import { processFeesBag } from "./utils/processFeeBag";

// yarn ts-node examples/wrapper/admin-withdraw-all-coins-coverage-fee.ts > admin-withdraw-all-coins-coverage-fee.log 2>&1
(async () => {
  const tx = new Transaction();

  const { deepReservesBagId } = await getWrapperBags();

  // Process both fee types
  const { coinsMapByCoinType } = await processFeesBag(deepReservesBagId);
  const coinTypes = Object.keys(coinsMapByCoinType);

  for (const coinType of coinTypes) {
    getWithdrawFeeTx({
      coinType,
      target: `${WRAPPER_PACKAGE_ID}::wrapper::withdraw_deep_reserves_coverage_fee_v2`,
      user,
      adminCapId: ADMIN_CAP_OBJECT_ID,
      transaction: tx,
    });
  }

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log("Withdraw all coins coverage fee: ", res);
})();

import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider } from "../common";
import { FUND_CUP_OBJECT_ID, NS_COIN_TYPE, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";

const FEE_COIN_TYPE = NS_COIN_TYPE;

// yarn ts-node examples/wrapper/withdraw-charged-fee.ts > withdraw-charged-fee.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::withdraw_charged_fee`,
    typeArguments: [FEE_COIN_TYPE],
    arguments: [tx.object(FUND_CUP_OBJECT_ID), tx.object(WRAPPER_OBJECT_ID)],
  });

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log(res);
})();

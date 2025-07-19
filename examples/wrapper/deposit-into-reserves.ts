import { coinWithBalance, Transaction } from "@mysten/sui/transactions";
import { keypair, provider } from "../common";
import { DEEP_COIN_TYPE, DEEP_DECIMALS, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";

// How many DEEP tokens to deposit (in human-readable format)
const DEEP_AMOUNT = 100; // Change this to the amount you want to deposit

// Convert human-readable amount to raw amount
const rawAmount = DEEP_AMOUNT * 10 ** DEEP_DECIMALS;

// yarn ts-node examples/wrapper/deposit-into-reserves.ts > deposit-into-reserves.log 2>&1
(async () => {
  const coin = coinWithBalance({ balance: rawAmount, type: DEEP_COIN_TYPE });

  const tx = new Transaction();

  // Call the deposit function with our split coin
  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::deposit_into_reserves`,
    arguments: [tx.object(WRAPPER_OBJECT_ID), coin],
  });

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log(res);
})();

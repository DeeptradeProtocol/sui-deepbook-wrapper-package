import { bcs } from "@mysten/sui/bcs";
import { Transaction } from "@mysten/sui/transactions";
import { user } from "../../common";
import { provider } from "../../common";
import { DEEP_DECIMALS, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../../constants";

export async function getDeepReservesBalance() {
  const tx = new Transaction();

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::deep_reserves`,
    arguments: [tx.object(WRAPPER_OBJECT_ID)],
  });

  const res = await provider.devInspectTransactionBlock({
    sender: user,
    transactionBlock: tx,
  });

  const { results } = res;

  if (!results || results.length !== 1) {
    throw new Error("[getDeepReservesBalanceInfo] No results found");
  }

  const { returnValues } = results[0];

  if (!returnValues || returnValues.length !== 1) {
    throw new Error("[getDeepReservesBalanceInfo] No return values found");
  }

  const deepReservesValueRaw = returnValues[0][0];
  const deepReservesValueDecoded = bcs.u64().parse(new Uint8Array(deepReservesValueRaw));
  const deepReservesValue = +deepReservesValueDecoded / 10 ** DEEP_DECIMALS;

  return {
    deepReserves: deepReservesValue.toString(),
    deepReservesRaw: deepReservesValueDecoded,
  };
}

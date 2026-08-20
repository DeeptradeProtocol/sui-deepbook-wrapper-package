import { bcs } from "@mysten/sui/bcs";
import { Transaction } from "@mysten/sui/transactions";
import { provider, DUMMY_PLACEHOLDER_ADDRESS } from "../../provider";
import { DEEP_DECIMALS, TREASURY_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID } from "../../constants";

export async function getDeepReservesBalance() {
  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::treasury::deep_reserves`,
    arguments: [tx.object(TREASURY_OBJECT_ID)],
  });

  tx.setSender(DUMMY_PLACEHOLDER_ADDRESS);

  const res = await provider.simulateTransaction({
    transaction: tx,
    checksEnabled: false,
    include: { commandResults: true },
  });

  const { commandResults } = res;

  if (!commandResults || commandResults.length !== 1) {
    throw new Error("[getDeepReservesBalanceInfo] No results found");
  }

  const { returnValues } = commandResults[0];

  if (!returnValues || returnValues.length !== 1) {
    throw new Error("[getDeepReservesBalanceInfo] No return values found");
  }

  const deepReservesValueRaw = returnValues[0].bcs;
  const deepReservesValueDecoded = bcs.u64().parse(deepReservesValueRaw);
  const deepReservesValue = +deepReservesValueDecoded / 10 ** DEEP_DECIMALS;

  return {
    deepReserves: deepReservesValue.toString(),
    deepReservesRaw: deepReservesValueDecoded,
  };
}

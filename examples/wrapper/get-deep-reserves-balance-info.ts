import { getDeepReservesBalance } from "./utils/getDeepReservesBalance";

// yarn ts-node examples/wrapper/get-deep-reserves-balance-info.ts > get-deep-reserves-balance-info.log 2>&1
(async () => {
  const deepReservesBalance = await getDeepReservesBalance();
  console.debug("Deep Reserves Balance Info: ", deepReservesBalance);
})();

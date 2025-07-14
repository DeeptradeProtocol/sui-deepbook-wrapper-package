import { getWrapperBags } from "./utils/getWrapperBags";
import { processFeesBag } from "./utils/processFeeBag";
import { printFeeSummary } from "./utils/printFeeSummary";

// yarn ts-node examples/wrapper/get-charged-fee-info.ts > charged-fee-info.log 2>&1
(async () => {
  const { deepReservesBagId, protocolFeesBagId } = await getWrapperBags();

  // Process both fee types
  const deepReservesFees = await processFeesBag(deepReservesBagId);
  const protocolFees = await processFeesBag(protocolFeesBagId);

  // Print summaries
  printFeeSummary("Deep Reserves Coverage Fees", deepReservesFees.coinsMapByCoinType, deepReservesFees.coinsMetadataMapByCoinType);
  printFeeSummary("Protocol Fees", protocolFees.coinsMapByCoinType, protocolFees.coinsMetadataMapByCoinType);
})();

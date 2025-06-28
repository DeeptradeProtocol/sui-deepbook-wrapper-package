import { getWrapperBags } from "./utils/getWrapperBags";
import { processFeesBag } from "./utils/processFeeBag";
import { processHistoricalFeeBag } from "./utils/processHistoricalFeeBag";
import { printFeeSummary } from "./utils/printFeeSummary";

// yarn ts-node examples/wrapper/get-complete-fee-info.ts > complete-fee-info.log 2>&1
(async () => {
  const { deepReservesBagId, protocolFeesBagId, historicalCoverageFeesBagId, historicalProtocolFeesBagId } =
    await getWrapperBags();

  console.log("=== CURRENT FEES ===");

  // Process current fee types
  const deepReservesFees = await processFeesBag(deepReservesBagId);
  const protocolFees = await processFeesBag(protocolFeesBagId);

  // Print current fees summaries
  printFeeSummary(
    "Current Deep Reserves Coverage Fees",
    deepReservesFees.coinsMapByCoinType,
    deepReservesFees.coinsMetadataMapByCoinType,
  );
  printFeeSummary("Current Protocol Fees", protocolFees.coinsMapByCoinType, protocolFees.coinsMetadataMapByCoinType);

  console.log("\n=== HISTORICAL FEES ===");

  // Process historical fee types
  const historicalCoverageFees = await processHistoricalFeeBag(historicalCoverageFeesBagId);
  const historicalProtocolFees = await processHistoricalFeeBag(historicalProtocolFeesBagId);

  // Print historical fees summaries
  printFeeSummary(
    "Historical Deep Reserves Coverage Fees",
    historicalCoverageFees.coinsMapByCoinType,
    historicalCoverageFees.coinsMetadataMapByCoinType,
  );
  printFeeSummary(
    "Historical Protocol Fees",
    historicalProtocolFees.coinsMapByCoinType,
    historicalProtocolFees.coinsMetadataMapByCoinType,
  );
})();

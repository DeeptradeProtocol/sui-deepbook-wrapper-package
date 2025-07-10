import { getWrapperBags } from "./utils/getWrapperBags";
import { processHistoricalFeeBag } from "./utils/processHistoricalFeeBag";
import { printFeeSummary } from "./utils/printFeeSummary";

// yarn ts-node examples/wrapper/get-historical-fee-info.ts > historical-fee-info.log 2>&1
(async () => {
  const { historicalCoverageFeesBagId, historicalProtocolFeesBagId } = await getWrapperBags();

  // Process both historical fee types
  const historicalCoverageFees = await processHistoricalFeeBag(historicalCoverageFeesBagId);
  const historicalProtocolFees = await processHistoricalFeeBag(historicalProtocolFeesBagId);

  // Print summaries
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

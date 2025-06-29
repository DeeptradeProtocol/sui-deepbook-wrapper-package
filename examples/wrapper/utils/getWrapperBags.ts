import { provider } from "../../common";
import { WRAPPER_OBJECT_ID } from "../../constants";

export async function getWrapperBags() {
  // Fetch the wrapper object using its ID
  const wrapperObjectResponse = await provider.getObject({
    id: WRAPPER_OBJECT_ID,
    options: { showContent: true },
  });

  // Extract the object data from the response
  if (!wrapperObjectResponse.data?.content || wrapperObjectResponse.data.content.dataType !== "moveObject") {
    throw new Error("Could not fetch wrapper object data");
  }

  const wrapperObject = wrapperObjectResponse.data.content.fields;

  // Get the bag IDs for current fees
  const deepReservesBagId = (wrapperObject as any).deep_reserves_coverage_fees?.fields?.id?.id;
  const protocolFeesBagId = (wrapperObject as any).protocol_fees?.fields?.id?.id;

  // Get the bag IDs for historical fees
  const historicalCoverageFeesBagId = (wrapperObject as any).historical_coverage_fees?.fields?.id?.id;
  const historicalProtocolFeesBagId = (wrapperObject as any).historical_protocol_fees?.fields?.id?.id;

  if (!deepReservesBagId) {
    throw new Error("Could not find deep_reserves_coverage_fees bag ID");
  }

  if (!protocolFeesBagId) {
    throw new Error("Could not find protocol_fees bag ID");
  }

  if (!historicalCoverageFeesBagId) {
    throw new Error("Could not find historical_coverage_fees bag ID");
  }

  if (!historicalProtocolFeesBagId) {
    throw new Error("Could not find historical_protocol_fees bag ID");
  }

  return {
    deepReservesBagId,
    protocolFeesBagId,
    historicalCoverageFeesBagId,
    historicalProtocolFeesBagId,
  };
}

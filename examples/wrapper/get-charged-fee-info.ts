import { provider } from "../common";
import { WRAPPER_OBJECT_ID } from "../constants";

// yarn ts-node examples/wrapper/get-charged-fee-info.ts > charged-fee-info.log 2>&1
(async () => {
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

  // Get the bag IDs for both fee types
  const deepReservesBagId = (wrapperObject as any).deep_reserves_coverage_fees?.fields?.id?.id;
  const protocolFeesBagId = (wrapperObject as any).protocol_fees?.fields?.id?.id;

  if (!deepReservesBagId) {
    throw new Error("Could not find deep_reserves_coverage_fees bag ID");
  }

  if (!protocolFeesBagId) {
    throw new Error("Could not find protocol_fees bag ID");
  }

  // Process both fee types
  const deepReservesFees = await processFeesBag(deepReservesBagId);
  const protocolFees = await processFeesBag(protocolFeesBagId);

  // Print summaries
  printFeeSummary("Deep Reserves Coverage Fees", deepReservesFees.coinSummary, deepReservesFees.coinMetadata);
  printFeeSummary("Protocol Fees", protocolFees.coinSummary, protocolFees.coinMetadata);
})();

interface CoinMetadata {
  symbol: string;
  decimals: number;
}

interface CoinSummary {
  [key: string]: bigint;
}

// Helper function to format amounts with proper decimal places
function formatAmount(amount: bigint, decimals: number): string {
  const amountStr = amount.toString().padStart(decimals + 1, "0");
  const decimalPoint = amountStr.length - decimals;
  const formattedAmount = amountStr.slice(0, decimalPoint) + (decimals > 0 ? "." + amountStr.slice(decimalPoint) : "");
  return formattedAmount.replace(/\.?0+$/, "");
}

// Fetch coin metadata for a specific coin type
async function getCoinMetadata(coinType: string): Promise<CoinMetadata> {
  try {
    const metadata = await provider.getCoinMetadata({ coinType });
    if (metadata) {
      return {
        symbol: metadata.symbol,
        decimals: metadata.decimals,
      };
    }
  } catch (error) {
    console.log(`Could not fetch metadata for ${coinType}: ${error}`);
  }
  return {
    symbol: coinType.split("::").pop() || "UNKNOWN",
    decimals: 9,
  };
}

// Process fees from a specific bag
async function processFeesBag(bagId: string): Promise<{
  coinSummary: CoinSummary;
  coinMetadata: { [key: string]: CoinMetadata };
}> {
  const coinSummary: CoinSummary = {};
  const coinMetadata: { [key: string]: CoinMetadata } = {};

  // Fetch all dynamic fields in the bag
  const dynamicFields = await provider.getDynamicFields({ parentId: bagId });

  // Fetch each field's content
  for (const field of dynamicFields.data) {
    const fieldObject = await provider.getDynamicFieldObject({
      parentId: bagId,
      name: field.name,
    });

    // Extract coin type and balance information
    if (fieldObject.data?.content?.dataType === "moveObject") {
      const objectType = fieldObject.data.content.type;
      const fields = fieldObject.data.content.fields;

      // The dynamic field object contains the balance in its 'value' field
      if (objectType.includes("0x2::balance::Balance<")) {
        // Extract the coin type from the object type
        const coinType = objectType.substring(
          objectType.indexOf("0x2::balance::Balance<") + "0x2::balance::Balance<".length,
          objectType.length - 2,
        );

        // Extract the balance from the 'value' field
        const balance = (fields as any).value;

        // Add to summary
        coinSummary[coinType] = (coinSummary[coinType] || BigInt(0)) + BigInt(balance);

        // Fetch coin metadata if we haven't already
        if (!coinMetadata[coinType]) {
          coinMetadata[coinType] = await getCoinMetadata(coinType);
        }
      }
    }
  }

  return { coinSummary, coinMetadata };
}

// Print summary of fees
function printFeeSummary(title: string, coinSummary: CoinSummary, coinMetadata: { [key: string]: CoinMetadata }) {
  console.log(`\n${title}:`);
  for (const [coinType, amount] of Object.entries(coinSummary)) {
    const metadata = coinMetadata[coinType];
    const formattedAmount = formatAmount(amount, metadata.decimals);
    console.log(`${metadata.symbol}: ${formattedAmount} (${amount} raw)`);
  }
}

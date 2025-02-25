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

  // Get the bag ID from the charged_fees field using type assertion
  const bagId = (wrapperObject as any).charged_fees?.fields?.id?.id;
  if (!bagId) {
    throw new Error("Could not find charged_fees bag ID");
  }

  // Fetch all dynamic fields in the bag
  const dynamicFields = await provider.getDynamicFields({ parentId: bagId });

  // Create a summary of coin types and amounts
  const coinSummary: { [key: string]: bigint } = {};
  // Store coin metadata for formatting
  const coinMetadata: { [key: string]: { symbol: string; decimals: number } } = {};

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
          try {
            const metadata = await provider.getCoinMetadata({ coinType });
            if (metadata) {
              coinMetadata[coinType] = {
                symbol: metadata.symbol,
                decimals: metadata.decimals,
              };
            }
          } catch (error) {
            console.log(`Could not fetch metadata for ${coinType}: ${error}`);
            coinMetadata[coinType] = { symbol: coinType.split("::").pop() || "UNKNOWN", decimals: 9 };
          }
        }
      }
    }
  }

  console.log("\nCoin Summary:");
  for (const [coinType, amount] of Object.entries(coinSummary)) {
    const metadata = coinMetadata[coinType] || { symbol: coinType.split("::").pop() || "UNKNOWN", decimals: 9 };
    const formattedAmount = formatAmount(amount, metadata.decimals);
    console.log(`${metadata.symbol}: ${formattedAmount} (${amount} raw)`);
  }
})();

// Helper function to format amounts with proper decimal places
function formatAmount(amount: bigint, decimals: number): string {
  const amountStr = amount.toString().padStart(decimals + 1, "0");
  const decimalPoint = amountStr.length - decimals;
  const formattedAmount = amountStr.slice(0, decimalPoint) + (decimals > 0 ? "." + amountStr.slice(decimalPoint) : "");

  // Remove trailing zeros after decimal point
  return formattedAmount.replace(/\.?0+$/, "");
}

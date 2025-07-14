import { CoinsMapByCoinType, CoinsMetadataMapByCoinType } from "./types";
import { provider } from "../../common";
import { getCoinMetadata } from "./getCoinMetadata";

// Process historical fees from a specific bag (stored as u256 values)
export async function processHistoricalFeeBag(bagId: string): Promise<{
  coinsMapByCoinType: CoinsMapByCoinType;
  coinsMetadataMapByCoinType: CoinsMetadataMapByCoinType;
}> {
  const coinsMapByCoinType: CoinsMapByCoinType = {};
  const coinsMetadataMapByCoinType: CoinsMetadataMapByCoinType = {};

  // Fetch all dynamic fields in the bag
  const dynamicFields = await provider.getDynamicFields({ parentId: bagId });

  // Fetch each field's content
  for (const field of dynamicFields.data) {
    const fieldObject = await provider.getDynamicFieldObject({
      parentId: bagId,
      name: field.name,
    });

    // Extract coin type and historical amount information
    if (fieldObject.data?.content?.dataType === "moveObject") {
      const fieldName = field.name;
      const fieldValue = fieldObject.data.content.fields;

      // The field name should contain the coin type information
      // Historical fees are stored as ChargedFeeKey<CoinType> -> u256
      if (fieldName && typeof fieldName === "object" && "type" in fieldName) {
        const nameType = (fieldName as any).type;

        // Extract coin type from the ChargedFeeKey<CoinType> type
        if (nameType.includes("ChargedFeeKey<")) {
          const coinType = nameType.substring(
            nameType.indexOf("ChargedFeeKey<") + "ChargedFeeKey<".length,
            nameType.length - 1,
          );

          // The historical amount is stored directly as u256 in the field value
          const historicalAmount = (fieldValue as any).value || fieldValue;

          // Add to summary
          coinsMapByCoinType[coinType] = BigInt(historicalAmount);

          // Fetch coin metadata if we haven't already
          if (!coinsMetadataMapByCoinType[coinType]) {
            coinsMetadataMapByCoinType[coinType] = await getCoinMetadata(coinType);
          }
        }
      }
    }
  }

  return { coinsMapByCoinType, coinsMetadataMapByCoinType };
}

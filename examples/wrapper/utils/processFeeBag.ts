import { CoinsMapByCoinType, CoinsMetadataMapByCoinType } from "./types";
import { provider } from "../../common";
import { getCoinMetadata } from "./getCoinMetadata";

// Process fees from a specific bag
export async function processFeesBag(bagId: string): Promise<{
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
          coinsMapByCoinType[coinType] = (coinsMapByCoinType[coinType] || BigInt(0)) + BigInt(balance);
  
          // Fetch coin metadata if we haven't already
          if (!coinsMetadataMapByCoinType[coinType]) {
            coinsMetadataMapByCoinType[coinType] = await getCoinMetadata(coinType);
          }
        }
      }
    }
  
    return { coinsMapByCoinType, coinsMetadataMapByCoinType };
  }
import { bcs } from "@mysten/sui/bcs";
import type { SuiClientTypes } from "@mysten/sui/client";
import { CoinsMapByCoinType, CoinsMetadataMapByCoinType } from "./types";
import { provider } from "../../provider";
import { getCoinMetadata } from "./getCoinMetadata";

type DynamicFieldsPage = {
  hasNextPage: boolean;
  cursor: string | null;
  dynamicFields: Array<
    SuiClientTypes.DynamicFieldEntry & {
      value?: SuiClientTypes.DynamicFieldValue;
    }
  >;
};

// gRPC may return 0x2 or the full 0x000…002 address form.
const BALANCE_TYPE_RE = /0x0*2::balance::Balance<(.+)>$/;

// Process fees from a specific bag
export async function processFeesBag(bagId: string): Promise<{
  coinsMapByCoinType: CoinsMapByCoinType;
  coinsMetadataMapByCoinType: CoinsMetadataMapByCoinType;
}> {
  const coinsMapByCoinType: CoinsMapByCoinType = {};
  const coinsMetadataMapByCoinType: CoinsMetadataMapByCoinType = {};

  let nextCursor: string | null | undefined = null;
  let hasNextPage = true;

  while (hasNextPage) {
    const page: DynamicFieldsPage = await provider.listDynamicFields({
      parentId: bagId,
      cursor: nextCursor,
      include: { value: true },
    });

    for (const field of page.dynamicFields) {
      // Fee bags are expected to only store Balance values; missing value or unexpected type is a contract/API bug.
      if (!field.value) {
        throw new Error(`Dynamic field ${field.fieldId} in bag ${bagId} has no value (expected Balance)`);
      }

      const match = field.value.type.match(BALANCE_TYPE_RE);
      if (!match) {
        throw new Error(
          `Unexpected dynamic field type in fee bag ${bagId}: ${field.value.type} (expected 0x2::balance::Balance<...>)`,
        );
      }

      const coinType = match[1];
      const balance = bcs.u64().parse(field.value.bcs);

      // Add to summary
      coinsMapByCoinType[coinType] = (coinsMapByCoinType[coinType] || BigInt(0)) + BigInt(balance);

      // Fetch coin metadata if we haven't already
      if (!coinsMetadataMapByCoinType[coinType]) {
        coinsMetadataMapByCoinType[coinType] = await getCoinMetadata(coinType);
      }
    }

    hasNextPage = page.hasNextPage;
    nextCursor = page.cursor;
  }

  return { coinsMapByCoinType, coinsMetadataMapByCoinType };
}

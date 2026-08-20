import { provider } from "../../provider";
import { TREASURY_OBJECT_ID } from "../../constants";

export async function getTreasuryBags() {
  const { object } = await provider.getObject({
    objectId: TREASURY_OBJECT_ID,
    include: { json: true },
  });

  const treasuryObject = object.json as Record<string, unknown> | null;
  if (!treasuryObject) {
    throw new Error("Could not fetch treasury object data");
  }

  const deepReservesBagId = (treasuryObject as any).deep_reserves_coverage_fees?.fields?.id?.id;
  const protocolFeesBagId = (treasuryObject as any).protocol_fees?.fields?.id?.id;

  if (!deepReservesBagId) {
    throw new Error("Could not find deep_reserves_coverage_fees bag ID");
  }

  if (!protocolFeesBagId) {
    throw new Error("Could not find protocol_fees bag ID");
  }

  return { deepReservesBagId, protocolFeesBagId };
}

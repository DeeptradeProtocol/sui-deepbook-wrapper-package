import { provider } from "../../provider";
import { TREASURY_OBJECT_ID } from "../../constants";

/** gRPC `include: { json: true }` returns Bag fields as `{ id, size }` (not JSON-RPC's nested `fields.id.id`). */
type TreasuryBagJson = {
  id?: string;
  size?: string;
};

type TreasuryObjectJson = {
  deep_reserves_coverage_fees?: TreasuryBagJson;
  protocol_fees?: TreasuryBagJson;
};

function isTreasuryObjectJson(value: unknown): value is TreasuryObjectJson {
  return typeof value === "object" && value !== null;
}

export async function getTreasuryBags() {
  const { object } = await provider.getObject({
    objectId: TREASURY_OBJECT_ID,
    include: { json: true },
  });

  if (!isTreasuryObjectJson(object.json)) {
    throw new Error("Could not fetch treasury object data");
  }

  const deepReservesBagId = object.json.deep_reserves_coverage_fees?.id;
  const protocolFeesBagId = object.json.protocol_fees?.id;

  if (!deepReservesBagId) {
    throw new Error("Could not find deep_reserves_coverage_fees bag ID");
  }

  if (!protocolFeesBagId) {
    throw new Error("Could not find protocol_fees bag ID");
  }

  return { deepReservesBagId, protocolFeesBagId };
}

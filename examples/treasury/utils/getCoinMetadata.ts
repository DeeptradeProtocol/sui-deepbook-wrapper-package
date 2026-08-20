import { provider } from "../../provider";
import { CoinMetadata } from "./types";

// Fetch coin metadata for a specific coin type
export async function getCoinMetadata(coinType: string): Promise<CoinMetadata> {
  try {
    const { coinMetadata } = await provider.getCoinMetadata({ coinType });
    if (coinMetadata) {
      return {
        symbol: coinMetadata.symbol,
        decimals: coinMetadata.decimals,
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

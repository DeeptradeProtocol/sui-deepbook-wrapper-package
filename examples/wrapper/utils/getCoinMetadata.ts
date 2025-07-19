import { provider } from "../../common";
import { CoinMetadata } from "./types";

// Fetch coin metadata for a specific coin type
export async function getCoinMetadata(coinType: string): Promise<CoinMetadata> {
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

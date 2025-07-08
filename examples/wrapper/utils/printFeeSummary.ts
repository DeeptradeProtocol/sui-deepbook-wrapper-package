import { CoinMetadata, CoinsMapByCoinType } from "./types";
import { formatAmount } from "./formatAmount";

// Print summary of fees
export function printFeeSummary(title: string, CoinsMapByCoinType: CoinsMapByCoinType, coinMetadata: { [key: string]: CoinMetadata }) {
    console.log(`\n${title}:`);
    for (const [coinType, amount] of Object.entries(CoinsMapByCoinType)) {
      const metadata = coinMetadata[coinType];
      const formattedAmount = formatAmount(amount, metadata.decimals);
      console.log(`${metadata.symbol}: ${formattedAmount} (${amount} raw)`);
    }
  }
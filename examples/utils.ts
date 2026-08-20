import { provider } from "./provider";

/**
 * Add two numbers.
 * @param {string} hexStr String as an input.
 * @return {Uint8Array} Encoded string into Uint8Array type.
 */
export function hexStringToUint8Array(hexStr: string) {
  if (hexStr.length % 2 !== 0) {
    throw new Error("Invalid hex string length.");
  }

  const byteValues: number[] = [];

  for (let i = 0; i < hexStr.length; i += 2) {
    const byte: number = parseInt(hexStr.slice(i, i + 2), 16);

    if (Number.isNaN(byte)) {
      throw new Error(`Invalid hex value at position ${i}: ${hexStr.slice(i, i + 2)}`);
    }

    byteValues.push(byte);
  }

  return new Uint8Array(byteValues);
}

/**
 * @param {string} mnemonic Seed phrase of the wallet.
 * @return {string} Normilized mnemonic (trimmed & etc.).
 */
export function normalizeMnemonic(mnemonic: string): string {
  return mnemonic
    .trim()
    .split(/\s+/)
    .map((part) => part.toLowerCase())
    .join(" ");
}

/**
 * Converts a percentage to a billionths representation
 * @param percentage - Percentage value
 * @returns Billionths representation of the percentage
 *
 * @example
 * percentageInBillionths(1) // 10_000_000
 */
export function percentageInBillionths(percentage: number) {
  return (percentage / 100) * 1_000_000_000;
}

// Helper function to format balance with decimals
export function formatBalance(balance: string | number | bigint, decimals: number = 9): string {
  const balanceBigInt = BigInt(balance);
  const amount = Number(balanceBigInt) / 10 ** decimals;
  return amount.toFixed(decimals).replace(/\.?0+$/, "");
}

/** Extract inner coin type from a `0x2::coin::Coin<T>` object type string. */
export function extractCoinType(coinObjectType: string): string {
  const prefix = "0x2::coin::Coin<";
  if (coinObjectType.startsWith(prefix) && coinObjectType.endsWith(">")) {
    return coinObjectType.slice(prefix.length, -1);
  }
  return coinObjectType;
}

/** Paginate through all coins owned by an address. */
export async function listAllCoins(
  owner: string,
  coinType?: string,
): Promise<
  Array<{
    objectId: string;
    version: string;
    digest: string;
    type: string;
    balance: string;
  }>
> {
  const coins: Array<{
    objectId: string;
    version: string;
    digest: string;
    type: string;
    balance: string;
  }> = [];
  let cursor: string | null | undefined = null;
  let hasNextPage = true;

  while (hasNextPage) {
    const response = await provider.listCoins({ owner, coinType, cursor });
    coins.push(...response.objects);
    cursor = response.cursor;
    hasNextPage = response.hasNextPage;
  }

  return coins;
}

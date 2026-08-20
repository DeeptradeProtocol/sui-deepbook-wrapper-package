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

import { Transaction } from "@mysten/sui/transactions";

/**
 * Appends commands to a transaction to send a specific amount of a coin balance to a recipient.
 * Uses `tx.balance` to consume both coins and address balances seamlessly.
 *
 * @param {Object} params - The parameters for sending the balance.
 * @param {string} params.coinType - The type of the coin to send (e.g., "0x2::sui::SUI").
 * @param {bigint} params.amount - The raw base-unit amount of the coin to send.
 * @param {string} params.recipientAddress - The address of the recipient.
 * @param {Transaction} params.tx - The transaction block to append the commands to.
 */
export function sendBalance({
  coinType,
  amount,
  recipientAddress,
  tx,
}: {
  coinType: string;
  amount: bigint;
  recipientAddress: string;
  tx: Transaction;
}): void {
  const balance = tx.balance({ type: coinType, balance: amount });

  tx.moveCall({
    target: "0x2::balance::send_funds",
    typeArguments: [coinType],
    arguments: [balance, tx.pure.address(recipientAddress)],
  });
}

/** Paginate through all balances owned by an address. */
export async function listAllBalances(
  owner: string,
): Promise<
  Array<{
    coinType: string;
    balance: string;
    coinBalance: string;
    addressBalance: string;
  }>
> {
  const balances = [];
  let cursor: string | null | undefined = null;
  let hasNextPage = true;

  while (hasNextPage) {
    const balancesResponse = await provider.listBalances({
      owner,
      cursor,
    });
    balances.push(...balancesResponse.balances);
    cursor = balancesResponse.cursor;
    hasNextPage = balancesResponse.hasNextPage;
  }

  return balances;
}

/**
 * Aggregates a list of coin objects by their inner coin type.
 * Returns an object mapping the coin type to its total count and total balance.
 */
export function aggregateCoinsByCoinType(
  coins: Array<{ type: string; balance: string }>,
): Record<string, { count: number; balance: bigint }> {
  const aggregated: Record<string, { count: number; balance: bigint }> = {};

  for (const coin of coins) {
    const type = extractCoinType(coin.type);
    if (!aggregated[type]) {
      aggregated[type] = { count: 0, balance: 0n };
    }
    aggregated[type].count += 1;
    aggregated[type].balance += BigInt(coin.balance);
  }

  return aggregated;
}

/** Paginate through all coins owned by an address. */
export async function listAllCoins(
  owner: string,
  coinType?: string,
): Promise<{
  coins: Array<{
    objectId: string;
    version: string;
    digest: string;
    type: string;
    balance: string;
  }>;
  aggregated: Record<string, { count: number; balance: bigint }>;
}> {
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

  const aggregated = aggregateCoinsByCoinType(coins);

  return { coins, aggregated };
}

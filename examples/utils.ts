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

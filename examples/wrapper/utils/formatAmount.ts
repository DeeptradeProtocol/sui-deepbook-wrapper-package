// Helper function to format amounts with proper decimal places
export function formatAmount(amount: bigint, decimals: number): string {
    const amountStr = amount.toString().padStart(decimals + 1, "0");
    const decimalPoint = amountStr.length - decimals;
    const formattedAmount = amountStr.slice(0, decimalPoint) + (decimals > 0 ? "." + amountStr.slice(decimalPoint) : "");
    return formattedAmount.replace(/\.?0+$/, "");
  }
  
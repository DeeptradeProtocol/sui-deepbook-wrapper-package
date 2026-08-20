import { Transaction } from "@mysten/sui/transactions";
import { SUI_COIN_TYPE } from "../constants";
import { provider } from "../provider";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { formatBalance, sendBalance, listAllCoins, listAllBalances } from "../utils";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";

const BUFFER_IN_SUI = 0.25;
const BUFFER_IN_MIST = BUFFER_IN_SUI * 1_000_000_000;

const DESTINATION_ADDRESS = process.env.DESTINATION_ADDRESS;
if (!DESTINATION_ADDRESS) {
  throw new Error("DESTINATION_ADDRESS environment variable is required.");
}

const SOURCE_ADDRESS = process.env.SOURCE_ADDRESS || MULTISIG_CONFIG.address;

// npx tsx examples/send-coins/send-coins-batch-to-destination.ts > logs/send-coins-batch.log 2>&1
(async () => {
  console.log(`\n========== SEND ALL COINS TO DESTINATION ==========`);
  console.log(`From address: ${SOURCE_ADDRESS}`);
  console.log(`To address: ${DESTINATION_ADDRESS || "(NOT SET)"}\n`);

  // Safety checks
  if (!DESTINATION_ADDRESS) {
    console.error(`❌ ERROR: DESTINATION_ADDRESS is not set!`);
    console.error(`Please edit the script and set DESTINATION_ADDRESS before running.\n`);
    process.exit(1);
  }

  if (DESTINATION_ADDRESS === SOURCE_ADDRESS) {
    console.error(`❌ ERROR: Destination address is the same as sender address!`);
    console.error(`This would be pointless. Please set a different address.\n`);
    process.exit(1);
  }

  console.log(`Fetching all balances from sender...\n`);

  // Fetch paginated balances
  const allBalances = await listAllBalances(SOURCE_ADDRESS);

  const { aggregated: allCoinsAggregated } = await listAllCoins(SOURCE_ADDRESS);

  const initialSuiBalance = allBalances.find((b) => b.coinType === SUI_COIN_TYPE || b.coinType.endsWith("::sui::SUI"));
  if (initialSuiBalance) {
    const rawSui = BigInt(initialSuiBalance.balance);
    console.log(`Initial SUI balance: ${formatBalance(rawSui)} SUI`);
    const suiCoinCount = allCoinsAggregated[SUI_COIN_TYPE]?.count || 0;
    console.log(`Initial SUI coin objects: ${suiCoinCount}`);
    const suiBuffer = BigInt(BUFFER_IN_MIST);
    console.log(`Buffer: ${formatBalance(suiBuffer)} SUI (to remain in wallet)`);
    if (rawSui > suiBuffer) {
      console.log(`To send: ${formatBalance(rawSui - suiBuffer)} SUI\n`);
    } else {
      console.log(`To send: 0 SUI (balance <= buffer)\n`);
    }
  } else {
    console.log(`Initial SUI balance: 0 SUI\n`);
  }

  console.log(`========== COINS TO SEND ==========`);
  console.log(`Found ${allBalances.length} unique coin types.`);

  const tx = new Transaction();
  let hasTransfers = false;

  for (const balanceInfo of allBalances) {
    const rawBalance = BigInt(balanceInfo.balance);
    const isSui = balanceInfo.coinType === SUI_COIN_TYPE || balanceInfo.coinType.endsWith("::sui::SUI");

    let amountToSend = rawBalance;

    if (isSui) {
      const suiBuffer = BigInt(BUFFER_IN_MIST);
      amountToSend = rawBalance > suiBuffer ? rawBalance - suiBuffer : 0n;
    }

    if (amountToSend > 0n) {
      const coinSymbol = balanceInfo.coinType.split("::").pop() || "UNKNOWN";
      
      const objectCount = allCoinsAggregated[balanceInfo.coinType]?.count || 0;
      console.log(`Preparing to send ${formatBalance(amountToSend)} ${coinSymbol} (${objectCount} object${objectCount === 1 ? '' : 's'})`);

      sendBalance({
        coinType: balanceInfo.coinType,
        amount: amountToSend,
        recipientAddress: DESTINATION_ADDRESS,
        tx,
      });

      hasTransfers = true;
    }
  }

  if (!hasTransfers) {
    console.log(`\nNo coins found with sufficient balance to send. Exiting.`);
    return;
  }

  console.log(`\n========== GENERATING TRANSACTION BYTES ==========\n`);

  try {
    await buildAndLogMultisigTransaction(tx, SOURCE_ADDRESS, undefined, false);
    console.log(`\n✅ Transaction prepared successfully.`);
  } catch (error) {
    console.error(`\n❌ Failed to build transaction:`);
    console.error(error instanceof Error ? error.message : String(error));
  }
})();

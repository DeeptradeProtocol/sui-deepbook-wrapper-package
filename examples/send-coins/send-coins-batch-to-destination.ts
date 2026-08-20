import { Transaction } from "@mysten/sui/transactions";
import { SUI_COIN_TYPE } from "../constants";
import { provider } from "../provider";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { formatBalance, extractCoinType, listAllCoins } from "../utils";
import { CoinGroup } from "./types";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";

// Maximum objects per transaction (conservative limit)
const MAX_OBJECTS_PER_PTB = 1500;
const BUFFER_IN_SUI = 3;
const BUFFER_IN_MIST = BUFFER_IN_SUI * 1_000_000_000;

const DESTINATION_ADDRESS = process.env.DESTINATION_ADDRESS;
if (!DESTINATION_ADDRESS) {
  throw new Error("DESTINATION_ADDRESS environment variable is required.");
}

// npx tsx examples/send-coins/send-coins-batch-to-destination.ts > logs/send-coins-batch.log 2>&1
(async () => {
  console.log(`\n========== SEND ALL COINS TO DESTINATION ==========`);
  console.log(`From address: ${MULTISIG_CONFIG.address}`);
  console.log(`To address: ${DESTINATION_ADDRESS || "(NOT SET)"}\n`);

  // Safety checks
  if (!DESTINATION_ADDRESS) {
    console.error(`❌ ERROR: DESTINATION_ADDRESS is not set!`);
    console.error(`Please edit the script and set DESTINATION_ADDRESS before running.\n`);
    process.exit(1);
  }

  if (DESTINATION_ADDRESS === MULTISIG_CONFIG.address) {
    console.error(`❌ ERROR: Destination address is the same as sender address!`);
    console.error(`This would be pointless. Please set a different address.\n`);
    process.exit(1);
  }

  // Get initial SUI balance
  const initialSuiBalance = await provider.getBalance({
    owner: MULTISIG_CONFIG.address,
    coinType: SUI_COIN_TYPE,
  });
  const initialSuiCoins = await listAllCoins(MULTISIG_CONFIG.address, SUI_COIN_TYPE);

  console.log(`Initial SUI balance: ${formatBalance(initialSuiBalance.balance.balance)} SUI`);
  console.log(`Initial SUI coin objects: ${initialSuiCoins.length}\n`);

  // Fetch all coins for the MULTISIG_CONFIG.address
  console.log(`Fetching all coins from sender...`);

  const coinGroups: Map<string, { objectIds: string[]; totalBalance: bigint }> = new Map();
  const allCoins = await listAllCoins(MULTISIG_CONFIG.address);

  for (const coin of allCoins) {
    const coinType = extractCoinType(coin.type);
    const existing = coinGroups.get(coinType) || { objectIds: [], totalBalance: 0n };
    existing.objectIds.push(coin.objectId);
    existing.totalBalance += BigInt(coin.balance);
    coinGroups.set(coinType, existing);
  }

  console.log(`Found ${coinGroups.size} unique coin types.\n`);

  // Separate SUI coins from other coins (SUI will be sent LAST)
  let suiCoins: string[] = [];
  const nonSuiCoins: CoinGroup[] = [];

  for (const [coinType, data] of coinGroups.entries()) {
    // Check if this is SUI (handles both 0x2::sui::SUI and full address formats)
    const isSuiCoin = coinType === SUI_COIN_TYPE || coinType.endsWith("::sui::SUI") || coinType === "0x2::sui::SUI";

    if (!isSuiCoin) {
      nonSuiCoins.push({ coinType, objectIds: data.objectIds, totalBalance: data.totalBalance });
    } else {
      // Collect all SUI coins
      suiCoins = data.objectIds;
    }
  }

  // Calculate SUI transfer amount based on buffer
  const totalSuiBalance = BigInt(initialSuiBalance.balance.balance);
  const suiBuffer = BigInt(BUFFER_IN_MIST);
  const amountSuiToSend = totalSuiBalance > suiBuffer ? totalSuiBalance - suiBuffer : 0n;

  // Display all coins to be sent
  console.log(`========== COINS TO SEND ==========`);
  console.log(`Non-SUI coins: ${nonSuiCoins.length} types`);
  for (const { coinType, objectIds, totalBalance } of nonSuiCoins) {
    const coinSymbol = coinType.split("::").pop() || "UNKNOWN";
    console.log(`  ${coinSymbol}: ${objectIds.length} objects, Total: ${formatBalance(totalBalance)}`);
  }

  console.log(`\nSUI balance:`);
  console.log(`  Total: ${formatBalance(totalSuiBalance)} SUI`);
  console.log(`  Buffer: ${formatBalance(suiBuffer)} SUI (to remain in wallet)`);
  if (amountSuiToSend > 0n) {
    console.log(`  To send: ${formatBalance(amountSuiToSend)} SUI`);
  } else {
    console.log(`  To send: 0 SUI (balance <= buffer)`);
  }
  console.log(``);

  if (nonSuiCoins.length === 0 && amountSuiToSend === 0n) {
    console.log(`No coins found to send. Exiting.`);
    return;
  }

  // Confirm before proceeding
  console.log(`⚠️  WARNING: This will prepare transactions to send coins to ${DESTINATION_ADDRESS}`);

  console.log(`\n========== BUILDING TRANSACTION PTBs ==========\n`);

  // ========== STEP 1: Build PTBs (Non-SUI + SUI in the last batch) ==========
  const ptbs: { tx: Transaction; description: string }[] = [];

  let currentTx = new Transaction();
  let currentObjectCount = 0;
  let coinsInCurrentBatch = 0;
  let ptbNumber = 0;

  // Process non-SUI coins first
  if (nonSuiCoins.length > 0) {
    for (const { coinType, objectIds } of nonSuiCoins) {
      // Check if adding this coin type would exceed limit
      if (currentObjectCount + objectIds.length > MAX_OBJECTS_PER_PTB && coinsInCurrentBatch > 0) {
        // Save current PTB and start a new one
        ptbNumber++;
        ptbs.push({
          tx: currentTx,
          description: `PTB #${ptbNumber} (${coinsInCurrentBatch} types, ${currentObjectCount} objects)`,
        });

        currentTx = new Transaction();
        currentObjectCount = 0;
        coinsInCurrentBatch = 0;
      }

      // Add all objects of this coin type to current PTB
      currentTx.transferObjects(
        objectIds.map((id) => currentTx.object(id)),
        currentTx.pure.address(DESTINATION_ADDRESS),
      );

      currentObjectCount += objectIds.length;
      coinsInCurrentBatch++;
    }
  }

  // Add SUI transfer to the current/last PTB if needed
  if (amountSuiToSend > 0n) {
    const [coinToSend] = currentTx.splitCoins(currentTx.gas, [currentTx.pure.u64(amountSuiToSend)]);
    currentTx.transferObjects([coinToSend], currentTx.pure.address(DESTINATION_ADDRESS));
  }

  // Push the final PTB
  if (coinsInCurrentBatch > 0 || amountSuiToSend > 0n) {
    ptbNumber++;
    const description =
      amountSuiToSend > 0n
        ? `Final PTB #${ptbNumber} (${coinsInCurrentBatch} types + SUI transfer)`
        : `Final PTB #${ptbNumber} (${coinsInCurrentBatch} types)`;

    ptbs.push({
      tx: currentTx,
      description,
    });
  }

  console.log(`Built ${ptbs.length} PTB(s) total.\n`);

  // ========== STEP 2: Generate Transaction Bytes ==========
  if (ptbs.length > 0) {
    console.log(`========== GENERATING TRANSACTION BYTES ==========\n`);

    let successfulBatches = 0;
    let failedBatches = 0;

    for (let i = 0; i < ptbs.length; i++) {
      const { tx, description } = ptbs[i];
      console.log(`Processing ${description}...`);

      try {
        await buildAndLogMultisigTransaction(tx);
        successfulBatches++;
      } catch (error) {
        console.error(`  ✗ Failed:`);
        console.error(`    Error: ${error instanceof Error ? error.message : String(error)}\n`);
        failedBatches++;
      }
    }

    console.log(`\nSummary: ${successfulBatches} transactions prepared, ${failedBatches} failed\n`);
  } else {
    console.log(`No transactions needed.\n`);
  }

  // Final summary
  console.log(`\n========== PREPARATION COMPLETE ==========`);
  console.log(`All transactions have been built and validated.`);
  console.log(`Please follow the multisig steps logged above to sign and execute them.`);
  console.log(`\n========================================\n`);
})();

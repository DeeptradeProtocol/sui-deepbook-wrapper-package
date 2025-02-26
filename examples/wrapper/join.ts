import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider, user } from "../common";
import { DEEP_COIN_TYPE, DEEP_DECIMALS, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";

// How many DEEP tokens to join (in human-readable format)
const DEEP_AMOUNT = 10; // Change this to the amount you want to join

// Convert human-readable amount to raw amount
const rawAmount = BigInt(DEEP_AMOUNT) * BigInt(10 ** DEEP_DECIMALS);

// yarn ts-node examples/wrapper/join.ts > join.log 2>&1
(async () => {
  // Get all DEEP objects owned by the user
  const userObjects = await provider.getOwnedObjects({
    owner: user,
    filter: {
      StructType: `0x2::coin::Coin<${DEEP_COIN_TYPE}>`,
    },
  });

  if (userObjects.data.length === 0) {
    throw new Error("No DEEP tokens found in user's wallet");
  }

  console.log(`Found ${userObjects.data.length} DEEP objects in wallet`);

  const tx = new Transaction();
  let deepCoinToUse;

  // If user has multiple DEEP objects, merge them first
  if (userObjects.data.length > 1) {
    console.log("Merging multiple DEEP objects...");
    const deepObjectIds = userObjects.data
      .map((obj) => obj.data?.objectId)
      .filter((id): id is string => id !== undefined);

    // Create a merged coin
    const [mergedCoin] = tx.mergeCoins(
      tx.object(deepObjectIds[0]),
      deepObjectIds.slice(1).map((id) => tx.object(id)),
    );
    deepCoinToUse = mergedCoin;
  } else {
    // Just use the single DEEP object
    const objectId = userObjects.data[0].data?.objectId;
    if (!objectId) throw new Error("Invalid DEEP object ID");
    deepCoinToUse = tx.object(objectId);
  }

  // Split the coin to get the exact amount we want to join
  const [coinToJoin] = tx.splitCoins(deepCoinToUse, [tx.pure.u64(rawAmount.toString())]);

  // Call the join function with our split coin
  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::join`,
    arguments: [tx.object(WRAPPER_OBJECT_ID), coinToJoin],
  });

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log(res);
})();

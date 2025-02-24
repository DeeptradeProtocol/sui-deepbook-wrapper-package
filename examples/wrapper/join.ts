import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider, user } from "../common";
import { DEEP_COIN_TYPE, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";

// Replace it by your actual DEEP object id, if you know it. Otherwise, it will be fetched from your wallet.
const DEEP_OBJECT_ID = null;

// yarn ts-node examples/wrapper/join.ts > join.log 2>&1
(async () => {
  let deepTokenId: string | null = DEEP_OBJECT_ID;

  if (!deepTokenId) {
    // Get all objects owned by the user that have type containing DEEP_COIN_TYPE
    const userObjects = await provider.getOwnedObjects({
      owner: user,
      filter: {
        StructType: DEEP_COIN_TYPE,
      },
    });

    if (userObjects.data.length === 0 || !userObjects.data[0].data?.objectId) {
      throw new Error("No DEEP tokens found in user's wallet");
    }

    deepTokenId = userObjects.data[0].data.objectId;
  }

  const tx = new Transaction();

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::router::join`,
    arguments: [tx.object(WRAPPER_OBJECT_ID), tx.object(deepTokenId)],
  });

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log(res);
})();

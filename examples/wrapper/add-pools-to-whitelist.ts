import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider } from "../common";
import {
  ADMIN_CAP_OBJECT_ID,
  WHITELIST_REGISTRY_OBJECT_ID,
  WRAPPER_PACKAGE_ID,
} from "../constants";

// List of pool IDs to whitelist
const poolIdsToWhitelist: string[] = [
  "0xb663828d6217467c8a1838a03793da896cbe745b150ebd57d82f814ca579fc22",
  "0xf948981b806057580f91622417534f491da5f61aeaf33d0ed8e69fd5691c95ce",
  "0xe05dafb5133bcffb8d59f4e12465dc0e9faeaa05e3e342a08fe135800e3e4407",
  "0x1109352b9112717bd2a7c3eb9a416fff1ba6951760f5bdd5424cf5e4e5b3e65c",
  "0xa0b9ebefb38c963fd115f52d71fa64501b79d1adcb5270563f92ce0442376545",
  "0x27c4fdb3b846aa3ae4a65ef5127a309aa3c1f466671471a806d8912a18b253e8",
  "0x0c0fdd4008740d81a8a7d4281322aee71a1b62c449eb5b142656753d89ebc060",
  "0x4e2ca3988246e1d50b9bf209abb9c1cbfec65bd95afdacc620a36c67bdb8452f",
  "0xe8e56f377ab5a261449b92ac42c8ddaacd5671e9fec2179d7933dd1a91200eec",
  "0x5661fc7f88fbeb8cb881150a810758cf13700bb4e1f31274a244581b37c303c3",
  "0x183df694ebc852a5f90a959f0f563b82ac9691e42357e9a9fe961d71a1b809c8",
  "0x126865a0197d6ab44bfd15fd052da6db92fd2eb831ff9663451bbfa1219e2af2",
  "0x2646dee5c4ad2d1ea9ce94a3c862dfd843a94753088c2507fea9223fd7e32a8f",
];

// yarn ts-node examples/wrapper/add-pools-to-whitelist.ts > add-pools-to-whitelist.log 2>&1
(async () => {
    const tx = new Transaction();

    // Add each pool to the whitelist in a single transaction
    for (const poolId of poolIdsToWhitelist) {
      tx.moveCall({
        target: `${WRAPPER_PACKAGE_ID}::whitelisted_pools::add_pool_to_whitelist`,
        arguments: [
          tx.object(ADMIN_CAP_OBJECT_ID),
          tx.object(WHITELIST_REGISTRY_OBJECT_ID),
          tx.object(poolId),
        ],
      });
    }

    const res = await provider.signAndExecuteTransaction({
      transaction: tx,
      signer: keypair,
    });

    console.log(res);
  }
)();

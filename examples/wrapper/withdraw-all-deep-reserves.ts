import { Transaction } from "@mysten/sui/transactions";
import { provider } from "../common";
import { ADMIN_CAP_OBJECT_ID, WRAPPER_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";
import { getDeepReservesBalance } from "./utils/getDeepReservesBalance";
import { buildAndLogMultisigTransaction, MULTISIG_CONFIG } from "../multisig";

// yarn ts-node examples/wrapper/withdraw-all-deep-reserves.ts > withdraw-all-deep-reserves.log 2>&1
(async () => {
  const tx = new Transaction();

  const { deepReservesRaw: amountToWithdraw, deepReserves: amountToWithdrawFormatted } = await getDeepReservesBalance();


  const withdrawnCoin = tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::withdraw_deep_reserves`,
    arguments: [
      tx.object(WRAPPER_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u64(amountToWithdraw),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.publicKeysSuiBytes),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
    ],
  });

  tx.transferObjects([withdrawnCoin], tx.pure.address(MULTISIG_CONFIG.address));
  console.warn(`Building transaction to withdraw ${amountToWithdrawFormatted} DEEP`);

  await buildAndLogMultisigTransaction(tx);
})();

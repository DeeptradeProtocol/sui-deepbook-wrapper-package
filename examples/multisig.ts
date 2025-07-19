import "dotenv/config";
import { fromBase64, toBase64 } from "@mysten/sui/utils";
import { MultiSigPublicKey } from "@mysten/sui/multisig";
import { Ed25519PublicKey } from "@mysten/sui/keypairs/ed25519";
import { Secp256k1PublicKey } from "@mysten/sui/keypairs/secp256k1";
import { Secp256r1PublicKey } from "@mysten/sui/keypairs/secp256r1";
import { PublicKey, SIGNATURE_FLAG_TO_SCHEME } from "@mysten/sui/cryptography";
import { provider } from "./common";
import { Transaction } from "@mysten/sui/transactions";

/**
 * Creates a public key instance from a Sui-standard Base64 string.
 * @param pk - The Base64-encoded, flagged public key.
 * @param scheme - The signature scheme for the public key.
 * @returns A PublicKey instance.
 */
function getPublicKey(pk: string): PublicKey {
  const bytes = fromBase64(pk);
  const scheme = SIGNATURE_FLAG_TO_SCHEME[bytes[0] as keyof typeof SIGNATURE_FLAG_TO_SCHEME];
  const rawKeyBytes = bytes.slice(1);

  switch (scheme) {
    case "ED25519": return new Ed25519PublicKey(rawKeyBytes);
    case "Secp256k1": return new Secp256k1PublicKey(rawKeyBytes);
    case "Secp256r1": return new Secp256r1PublicKey(rawKeyBytes);
    default: throw new Error(`Unsupported signature scheme flag: ${bytes[0]}`);
  }
}

/**
 * Derives a multisig address from the provided public keys, weights, and threshold.
 * @returns The derived multisig address.
 */
function deriveMultisigAddress(
  publicKeys: PublicKey[],
  weights: number[],
  threshold: number,
): string {
  const multisigPublicKey = MultiSigPublicKey.fromPublicKeys({
    publicKeys: publicKeys.map((pk, i) => ({
      publicKey: pk,
      weight: weights[i],
    })),
    threshold,
  });

  return multisigPublicKey.toSuiAddress();
}

interface MultisigConfig {
  /** The PublicKey instances of the signers for the multisig wallet. */
  publicKeys: PublicKey[];
  /** The Sui-standard byte representation of each signer's public key (flag || raw_bytes). */
  publicKeysSuiBytes: number[][];
  /** The weights of each signer in the multisig wallet. */
  weights: number[];
  /** The threshold required for a transaction to be approved. */
  threshold: number;
  /** The address of the multisig wallet. */
  address: string;
}

const signersBase64 = process.env.MULTISIG_SIGNERS_BASE64_PUBKEYS;
const weights = process.env.MULTISIG_WEIGHTS;
const threshold = process.env.MULTISIG_THRESHOLD;
const address = process.env.MULTISIG_ADDRESS;

if (!signersBase64 || !weights || !threshold || !address) {
  throw new Error(
    "Please provide MULTISIG_SIGNERS_BASE64_PUBKEYS, MULTISIG_WEIGHTS, MULTISIG_THRESHOLD, and MULTISIG_ADDRESS in your .env file",
  );
}

const multisigSignersBase64Pubkeys = signersBase64.split(",").map((s) => s.trim());
const parsedWeights = weights.split(",").map((w) => parseInt(w.trim(), 10));
const parsedThreshold = parseInt(threshold, 10);

if (
  multisigSignersBase64Pubkeys.length !== parsedWeights.length
) {
  throw new Error("The number of public keys and weights must be the same.");
}

const publicKeys = multisigSignersBase64Pubkeys.map((pk, i) => {
  try {
    return getPublicKey(pk);
  } catch (error: any) {
    throw new Error(
      `The public key at index ${i} ("${pk.substring(
        0,
        10,
      )}...") is invalid: ${error.message}`,
    );
  }
});

const publicKeysSuiBytes: number[][] = publicKeys.map((pk) => Array.from(pk.toSuiBytes()));

const derivedAddress = deriveMultisigAddress(
  publicKeys,
  parsedWeights,
  parsedThreshold,
);

if (derivedAddress !== address) {
  throw new Error(
    `The derived multisig address (${derivedAddress}) does not match the provided address (${address}). Please check your .env configuration.`,
  );
}

export const MULTISIG_CONFIG: MultisigConfig = {
  publicKeys,
  publicKeysSuiBytes,
  weights: parsedWeights,
  threshold: parsedThreshold,
  address,
};

console.debug("Multisig Config Loaded and Verified:");
console.debug(`- Multisig Address: ${MULTISIG_CONFIG.address}`);
console.debug("- Signer Details:");
MULTISIG_CONFIG.publicKeys.forEach((pk, i) => {
  const scheme = SIGNATURE_FLAG_TO_SCHEME[pk.flag() as keyof typeof SIGNATURE_FLAG_TO_SCHEME];
  console.debug(
    `  - Signer ${i + 1} (${scheme}): ${pk.toSuiAddress()}`,
  );
});
console.debug(`- Sui Public Key Bytes (for transactions): `, MULTISIG_CONFIG.publicKeysSuiBytes);
console.debug(`- Weights: ${JSON.stringify(MULTISIG_CONFIG.weights)}`);
console.debug(`- Threshold: ${JSON.stringify(MULTISIG_CONFIG.threshold)}`);

/**
 * Handles the boilerplate of building, dry running, and logging a multisig transaction.
 * @param tx - The transaction block to process.
 */
export async function buildAndLogMultisigTransaction(tx: Transaction): Promise<void> {
  tx.setSender(MULTISIG_CONFIG.address);

  const transactionBytes = await tx.build({ client: provider });
  const base64TxBytes = toBase64(transactionBytes);
  console.log("\nTransaction bytes (base64):", base64TxBytes);

  console.log("\n🔍 Performing dry run to validate transaction...");
  const dryRunResult = await provider.dryRunTransactionBlock({
    transactionBlock: transactionBytes,
  });

  console.log("Transaction validation:", dryRunResult.effects.status.status);

  if (dryRunResult.effects.status.status === "success") {
    console.log("✅ Transaction is valid");
    console.log("\n📋 Next steps:");
    console.log("1. Share these transaction bytes with the other signers.");
    console.log("2. Each signer must sign the transaction bytes using `sui keytool sign`.");
    console.log(
      "3. Combine the signatures using `sui keytool multi-sig-combine-partial-sig`.",
    );
    console.log("4. Execute the combined transaction using `sui client execute-signed-tx`.");
  } else {
    console.log("❌ Transaction validation failed:", dryRunResult.effects.status.error);
  }
}
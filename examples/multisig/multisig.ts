import "dotenv/config";
import { SIGNATURE_FLAG_TO_SCHEME } from "@mysten/sui/cryptography";
import { MultisigConfig } from "./types";
import { deriveMultisigAddress, getPublicKey } from "./utils";

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

if (multisigSignersBase64Pubkeys.length !== parsedWeights.length) {
  throw new Error("The number of public keys and weights must be the same.");
}

const publicKeys = multisigSignersBase64Pubkeys.map((pk, i) => {
  try {
    return getPublicKey(pk);
  } catch (error: any) {
    throw new Error(`The public key at index ${i} ("${pk.substring(0, 10)}...") is invalid: ${error.message}`);
  }
});

const publicKeysSuiBytes: number[][] = publicKeys.map((pk) => Array.from(pk.toSuiBytes()));

const derivedAddress = deriveMultisigAddress(publicKeys, parsedWeights, parsedThreshold);

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
console.debug(`- Weights: ${JSON.stringify(MULTISIG_CONFIG.weights)}`);
console.debug(`- Threshold: ${JSON.stringify(MULTISIG_CONFIG.threshold)}`);
console.debug("- Signer Details:");
MULTISIG_CONFIG.publicKeys.forEach((pk, i) => {
  const scheme = SIGNATURE_FLAG_TO_SCHEME[pk.flag() as keyof typeof SIGNATURE_FLAG_TO_SCHEME];
  console.debug(`  - Signer ${i + 1} (${scheme}): ${pk.toSuiAddress()}`);
});
console.debug(`- Sui Public Key Bytes (for transactions): `, MULTISIG_CONFIG.publicKeysSuiBytes);

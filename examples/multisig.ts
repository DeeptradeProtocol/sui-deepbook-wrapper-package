import "dotenv/config";
import { fromBase64 } from "@mysten/sui/utils";

/**
 * Converts a base64 encoded public key to a byte array.
 * Used for multisig operations where public keys are provided in base64 format.
 *
 * @param base64 - Base64 encoded public key string.
 * @returns Array of numbers representing the public key bytes.
 */
function base64ToBytes(base64: string): number[] {
  return Array.from(fromBase64(base64));
}

interface MultisigConfig {
  /**
   * The addresses of the signers for the multisig wallet.
   */
  signers: string[];
  /**
   * The weights of each signer in the multisig wallet.
   */
  weights: number[];
  /**
   * The threshold required for a transaction to be approved.
   */
  threshold: number;
  /**
   * The address of the multisig wallet.
   */
  address: string;
  /**
   * The public keys of the signers, converted to byte arrays.
   */
  pks: number[][];
}

const signers = process.env.MULTISIG_SIGNERS_BASE64_PUBKEYS;
const weights = process.env.MULTISIG_WEIGHTS;
const threshold = process.env.MULTISIG_THRESHOLD;
const address = process.env.MULTISIG_ADDRESS;

if (!signers || !weights || !threshold || !address) {
  throw new Error(
    "Please provide MULTISIG_SIGNERS_BASE64_PUBKEYS, MULTISIG_WEIGHTS, MULTISIG_THRESHOLD, and MULTISIG_ADDRESS in your .env file",
  );
}

const multisigSignersBase64Pubkeys = signers.split(",");
const parsedWeights = weights.split(",").map((w) => parseInt(w.trim(), 10));
const parsedThreshold = parseInt(threshold, 10);
const pks = multisigSignersBase64Pubkeys.map((pubkey) => base64ToBytes(pubkey));

export const MULTISIG_CONFIG: MultisigConfig = {
  signers: multisigSignersBase64Pubkeys,
  weights: parsedWeights,
  threshold: parsedThreshold,
  address,
  pks,
};

console.log("Multisig Config Loaded:");
console.log(`- Address: ${MULTISIG_CONFIG.address}`);
console.log(`- Signers: ${JSON.stringify(MULTISIG_CONFIG.signers)}`);
console.log(`- Signer public keys (bytes): converted and ready for transaction building`);
console.log(`- Weights: ${JSON.stringify(MULTISIG_CONFIG.weights)}`);
console.log(`- Threshold: ${MULTISIG_CONFIG.threshold}`);

import "dotenv/config";

import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { hexStringToUint8Array, normalizeMnemonic } from "./utils";

if (!process.env.SUI_WALLET_SEED_PHRASE?.length && !process.env.SUI_WALLET_PRIVATE_KEY_ARRAY?.length) {
  throw new Error("Empty mnemonic or private key");
}

export const mnemonic = normalizeMnemonic(process.env.SUI_WALLET_SEED_PHRASE ?? "");

// Handle different private key formats
function getKeypairFromPrivateKey(privateKey: string): Ed25519Keypair {
  // Check if it's a bech32 encoded key (starts with suiprivkey)
  if (privateKey.startsWith("suiprivkey")) {
    return Ed25519Keypair.fromSecretKey(privateKey);
  }
  // Otherwise, treat it as a hex string array
  return Ed25519Keypair.fromSecretKey(hexStringToUint8Array(privateKey));
}

export const keypair = process.env.SUI_WALLET_PRIVATE_KEY_ARRAY
  ? getKeypairFromPrivateKey(process.env.SUI_WALLET_PRIVATE_KEY_ARRAY)
  : Ed25519Keypair.deriveKeypair(mnemonic);

export const user = keypair.getPublicKey().toSuiAddress();

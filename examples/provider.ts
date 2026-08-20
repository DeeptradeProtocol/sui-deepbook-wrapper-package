import { SuiGrpcClient } from "@mysten/sui/grpc";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

export const suiProviderUrl = "https://fullnode.mainnet.sui.io:443";
export const provider = new SuiGrpcClient({
  network: "mainnet",
  baseUrl: suiProviderUrl,
});

/**
 * A randomly generated Sui address used as a placeholder for read-only operations.
 *
 * @note Use this ONLY for `simulateTransaction` or dry-runs where a sender
 * address is required but no actual signing/gas payment occurs.
 * @warning Never send real assets to this address as the private key is not persisted.
 */
export const DUMMY_PLACEHOLDER_ADDRESS = new Ed25519Keypair().getPublicKey().toSuiAddress();

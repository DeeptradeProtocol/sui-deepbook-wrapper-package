import { GrpcWebFetchTransport, SuiGrpcClient } from "@mysten/sui/grpc";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

// Optional custom RPC config: when provided, we use it instead of the default fullnode.
const CUSTOM_SUI_RPC_URL = process.env.CUSTOM_SUI_RPC_URL;
const CUSTOM_SUI_RPC_TOKEN = process.env.CUSTOM_SUI_RPC_TOKEN;
const CUSTOM_SUI_RPC_AUTH_HEADER: string | undefined =
  process.env.CUSTOM_SUI_RPC_AUTH_HEADER && typeof process.env.CUSTOM_SUI_RPC_AUTH_HEADER === "string"
    ? process.env.CUSTOM_SUI_RPC_AUTH_HEADER
    : undefined;

const baseUrl = CUSTOM_SUI_RPC_URL || "https://fullnode.mainnet.sui.io:443";

export const suiProviderUrl = baseUrl;
export const provider = new SuiGrpcClient({
  network: "mainnet",
  transport: new GrpcWebFetchTransport({
    baseUrl,
    meta:
      CUSTOM_SUI_RPC_TOKEN && CUSTOM_SUI_RPC_AUTH_HEADER
        ? { [CUSTOM_SUI_RPC_AUTH_HEADER]: CUSTOM_SUI_RPC_TOKEN }
        : undefined,
  }),
});

/**
 * A randomly generated Sui address used as a placeholder for read-only operations.
 *
 * @note Use this ONLY for `simulateTransaction` or dry-runs where a sender
 * address is required but no actual signing/gas payment occurs.
 * @warning Never send real assets to this address as the private key is not persisted.
 */
export const DUMMY_PLACEHOLDER_ADDRESS = new Ed25519Keypair().getPublicKey().toSuiAddress();

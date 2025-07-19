import { fromBase64 } from "@mysten/sui/utils";
import { MultiSigPublicKey } from "@mysten/sui/multisig";
import { Ed25519PublicKey } from "@mysten/sui/keypairs/ed25519";
import { Secp256k1PublicKey } from "@mysten/sui/keypairs/secp256k1";
import { Secp256r1PublicKey } from "@mysten/sui/keypairs/secp256r1";
import { PublicKey, SIGNATURE_FLAG_TO_SCHEME } from "@mysten/sui/cryptography";
/**
 * Creates a public key instance from a Sui-standard Base64 string.
 * @param pk - The Base64-encoded, flagged public key.
 * @param scheme - The signature scheme for the public key.
 * @returns A PublicKey instance.
 */
export function getPublicKey(pk: string): PublicKey {
  const bytes = fromBase64(pk);
  const scheme = SIGNATURE_FLAG_TO_SCHEME[bytes[0] as keyof typeof SIGNATURE_FLAG_TO_SCHEME];
  const rawKeyBytes = bytes.slice(1);

  switch (scheme) {
    case "ED25519":
      return new Ed25519PublicKey(rawKeyBytes);
    case "Secp256k1":
      return new Secp256k1PublicKey(rawKeyBytes);
    case "Secp256r1":
      return new Secp256r1PublicKey(rawKeyBytes);
    default:
      throw new Error(`Unsupported signature scheme flag: ${bytes[0]}`);
  }
}

/**
 * Derives a multisig address from the provided public keys, weights, and threshold.
 * @returns The derived multisig address.
 */
export function deriveMultisigAddress(publicKeys: PublicKey[], weights: number[], threshold: number): string {
  const multisigPublicKey = MultiSigPublicKey.fromPublicKeys({
    publicKeys: publicKeys.map((pk, i) => ({
      publicKey: pk,
      weight: weights[i],
    })),
    threshold,
  });

  return multisigPublicKey.toSuiAddress();
}

import { PublicKey } from "@mysten/sui/cryptography";

export interface MultisigConfig {
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

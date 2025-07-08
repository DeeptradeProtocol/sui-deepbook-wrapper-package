export interface CoinMetadata {
    symbol: string;
    decimals: number;
}
  
export interface CoinsMapByCoinType {
    [coinType: string]: bigint;
}

export interface CoinsMetadataMapByCoinType {
    [coinType: string]: CoinMetadata;
}
  
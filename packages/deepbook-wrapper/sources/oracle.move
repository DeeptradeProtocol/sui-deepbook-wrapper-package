module deepbook_wrapper::oracle;

use deepbook_wrapper::admin::AdminCap;
use pyth::price::Price;
use pyth::price_identifier::PriceIdentifier;
use pyth::price_info::PriceInfoObject;
use sui::clock::Clock;

// === Constants ===
/// Min confidence ratio of X means that the confidence interval must be less than (100/X)% of the price
const MIN_CONFIDENCE_RATIO: u64 = 20;

/// Maximum allowed price staleness in seconds
const MAX_STALENESS_SECONDS: u64 = 60;

/// Initial DEEP price feed id (used during initialization)
const INITIAL_DEEP_PRICE_FEED_ID: vector<u8> =
    x"29bdd5248234e33bd93d3b81100b5fa32eaa5997843847e2c2cb16d7c6d9f7ff";

/// Initial SUI price feed id (used during initialization)
const INITIAL_SUI_PRICE_FEED_ID: vector<u8> =
    x"23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744";

// === Structs ===
/// Configuration object that stores the current price feed IDs
public struct OracleConfig has key {
    id: UID,
    deep_price_feed_id: vector<u8>,
    sui_price_feed_id: vector<u8>,
}

// === Errors ===
#[error]
const EPriceConfidenceExceedsThreshold: vector<u8> =
    b"Oracle price confidence interval exceeds threshold";

#[error]
const EStalePrice: vector<u8> = b"Oracle price is stale";

#[error]
const EZeroPriceMagnitude: vector<u8> = b"Price magnitude is zero";

// === Public-Mutative Functions ===
/// Update the DEEP price feed ID
public fun update_deep_price_feed_id(
    config: &mut OracleConfig,
    _admin_cap: &AdminCap,
    new_feed_id: vector<u8>,
) {
    config.deep_price_feed_id = new_feed_id;
}

/// Update the SUI price feed ID
public fun update_sui_price_feed_id(
    config: &mut OracleConfig,
    _admin_cap: &AdminCap,
    new_feed_id: vector<u8>,
) {
    config.sui_price_feed_id = new_feed_id;
}

/// Update both price feed IDs at once
public fun update_price_feed_ids(
    config: &mut OracleConfig,
    _admin_cap: &AdminCap,
    new_deep_feed_id: vector<u8>,
    new_sui_feed_id: vector<u8>,
) {
    config.deep_price_feed_id = new_deep_feed_id;
    config.sui_price_feed_id = new_sui_feed_id;
}

// === Public-View Functions ===
/// Retrieves and validates the price from Pyth oracle
/// This function performs the following validation steps:
/// 1. Extracts the price and confidence interval from the Pyth price feed
/// 2. Validates the price reliability through:
///    - Confidence interval check: ensures price uncertainty is within acceptable bounds (≤10%)
///    - Staleness check: ensures price is not older than the maximum allowed age
/// 3. Returns the validated price if all checks pass, aborts otherwise
///
/// Parameters:
/// - price_info_object: The Pyth price info object containing the latest price data
/// - clock: System clock for timestamp verification
///
/// Returns:
/// - Price: The validated price
/// - PriceIdentifier: The identifier of the price feed
///
/// Aborts:
/// - With EPriceConfidenceExceedsThreshold if price uncertainty exceeds (100/MIN_CONFIDENCE_RATIO)% = 5% of the price
/// - With EStalePrice if price is older than MAX_STALENESS_SECONDS (60 seconds)
public fun get_pyth_price(
    price_info_object: &PriceInfoObject,
    clock: &Clock,
): (Price, PriceIdentifier) {
    let price_info = price_info_object.get_price_info_from_price_info_object();
    let price_feed = price_info.get_price_feed();
    let price_identifier = price_feed.get_price_identifier();
    let price = price_feed.get_price();
    let price_mag = price.get_price().get_magnitude_if_positive();
    let conf = price.get_conf();

    // Check price magnitude. If it's zero, the price will be rejected.
    assert!(price_mag > 0, EZeroPriceMagnitude);

    // Check price confidence interval. We want to make sure that:
    // (conf / price) * 100 <= (100 / MIN_CONFIDENCE_RATIO)% -> conf * MIN_CONFIDENCE_RATIO <= price.
    // That means the maximum price uncertainty is (100 / MIN_CONFIDENCE_RATIO)% = 5% of the price.
    // If it's higher, the price will be rejected.
    assert!(conf * MIN_CONFIDENCE_RATIO <= price_mag, EPriceConfidenceExceedsThreshold);

    // Check price staleness. If the price is stale, it will be rejected.
    let cur_time_s = clock.timestamp_ms() / 1000;
    let price_timestamp = price.get_timestamp();
    assert!(
        cur_time_s <= price_timestamp || cur_time_s - price_timestamp <= MAX_STALENESS_SECONDS,
        EStalePrice,
    );

    (price, price_identifier)
}

/// Get the current DEEP price feed ID from configuration
public fun get_deep_price_feed_id(config: &OracleConfig): vector<u8> {
    config.deep_price_feed_id
}

/// Get the current SUI price feed ID from configuration
public fun get_sui_price_feed_id(config: &OracleConfig): vector<u8> {
    config.sui_price_feed_id
}

/// Get both price feed IDs from configuration
public fun get_price_feed_ids(config: &OracleConfig): (vector<u8>, vector<u8>) {
    (config.deep_price_feed_id, config.sui_price_feed_id)
}

// === Private Functions ===
/// Initialize the oracle configuration with default price feed IDs
fun init(ctx: &mut TxContext) {
    let config = OracleConfig {
        id: object::new(ctx),
        deep_price_feed_id: INITIAL_DEEP_PRICE_FEED_ID,
        sui_price_feed_id: INITIAL_SUI_PRICE_FEED_ID,
    };
    transfer::share_object(config);
}

#[test_only]
public fun create_oracle_config_for_testing(
    deep_feed_id: vector<u8>,
    sui_feed_id: vector<u8>,
    ctx: &mut TxContext,
): OracleConfig {
    OracleConfig {
        id: object::new(ctx),
        deep_price_feed_id: deep_feed_id,
        sui_price_feed_id: sui_feed_id,
    }
}

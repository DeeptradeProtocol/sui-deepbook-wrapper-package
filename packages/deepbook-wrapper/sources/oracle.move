module deepbook_wrapper::oracle;

use pyth::price::Price;
use pyth::price_identifier::PriceIdentifier;
use pyth::price_info::PriceInfoObject;
use sui::clock::Clock;

// === Errors ===
/// Error when the price confidence interval exceeds the threshold
const EPriceConfidenceExceedsThreshold: u64 = 1;

/// Error when the price is stale
const EStalePrice: u64 = 2;

/// Error when the price magnitude is zero
const EZeroPriceMagnitude: u64 = 3;

// === Constants ===
/// Min confidence ratio of X means that the confidence interval must be less than (100/X)% of the price
const MIN_CONFIDENCE_RATIO: u64 = 20;

/// Maximum allowed price staleness in seconds
const MAX_STALENESS_SECONDS: u64 = 60;

/// DEEP price feed id
const DEEP_PRICE_FEED_ID: vector<u8> =
    x"29bdd5248234e33bd93d3b81100b5fa32eaa5997843847e2c2cb16d7c6d9f7ff";

/// SUI price feed id
const SUI_PRICE_FEED_ID: vector<u8> =
    x"23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744";

// === Public-View Functions ===
/// Retrieves and validates the price from Pyth oracle
/// This function performs the following validation steps:
/// 1. Extracts the price and confidence interval from the Pyth price feed
/// 2. Validates the price reliability through:
///    - Confidence interval check: ensures price uncertainty is within acceptable bounds (≤5%)
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

public fun deep_price_feed_id(): vector<u8> {
    DEEP_PRICE_FEED_ID
}

public fun sui_price_feed_id(): vector<u8> {
    SUI_PRICE_FEED_ID
}

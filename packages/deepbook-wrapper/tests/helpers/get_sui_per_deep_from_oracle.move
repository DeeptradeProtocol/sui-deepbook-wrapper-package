#[test_only]
module deepbook_wrapper::get_sui_per_deep_from_oracle_tests;

use deepbook_wrapper::helper::{get_sui_per_deep_from_oracle, EInvalidPriceFeedIdentifier};
use deepbook_wrapper::oracle::{
    Self,
    EPriceConfidenceExceedsThreshold,
    EStalePrice,
    EZeroPriceMagnitude
};
use pyth::i64;
use pyth::price;
use pyth::price_feed;
use pyth::price_identifier;
use pyth::price_info::{Self, PriceInfoObject};
use std::unit_test::assert_eq;
use sui::clock;
use sui::test_scenario::{Self, Scenario};

const MAX_POSITIVE_MAGNITUDE: u64 = (1 << 63) - 1; // 9223372036854775807

#[test, expected_failure(abort_code = EPriceConfidenceExceedsThreshold)]
fun deep_price_object_is_out_of_confidence() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with high confidence interval (>10% of price)
    // If price is 100 and confidence is 11, then conf * 10 (MIN_CONFIDENCE_RATIO) > price
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        11, // confidence (11 * 10 > 100, so price is out of confidence)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Create valid SUI price
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (5 * 10 < 100, so price is within confidence)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Function should abort when DEEP price is out of confidence
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EStalePrice)]
fun deep_price_object_is_stale() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);

    // Create clock with current timestamp
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    // Set current time to just over max staleness (60 seconds)
    let current_time = 61_000; // 61 seconds in milliseconds
    clock::set_for_testing(&mut clock, current_time);

    // Create stale DEEP price (timestamp = 0)
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        0, // timestamp (stale)
    );

    // Create fresh SUI price with current timestamp
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // timestamp (fresh)
    );

    // Function should abort when DEEP price is stale (> 60 seconds old)
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}
#[test, expected_failure(abort_code = EPriceConfidenceExceedsThreshold)]
fun sui_price_object_is_out_of_confidence() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create valid DEEP price with normal confidence interval
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (5 * 10 < 100, so price is within confidence)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Create SUI price with high confidence interval (>10% of price)
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        11, // confidence (11 * 10 > 100, so price is out of confidence)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Function should abort when SUI price is out of confidence
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EStalePrice)]
fun sui_price_object_is_stale() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);

    // Create clock with current timestamp
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    // Set current time to just over max staleness (60 seconds)
    let current_time = 61_000; // 61 seconds in milliseconds
    clock::set_for_testing(&mut clock, current_time);

    // Create fresh DEEP price with current timestamp
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // timestamp (fresh)
    );

    // Create stale SUI price (timestamp = 0)
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        0, // timestamp (stale)
    );

    // Function should abort when SUI price is stale (> 60 seconds old)
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EPriceConfidenceExceedsThreshold)]
fun both_prices_are_out_of_confidence() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with high confidence interval
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        11, // confidence (11 * 10 > 100, so price is out of confidence)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Create SUI price also with high confidence interval
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        12, // confidence (12 * 10 > 100, so price is out of confidence)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Function should abort when both prices are out of confidence
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EStalePrice)]
fun both_prices_are_stale() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);

    // Create clock with current timestamp
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    // Set current time to just over max staleness (60 seconds)
    let current_time = 61_000; // 61 seconds in milliseconds
    clock::set_for_testing(&mut clock, current_time);

    // Create stale DEEP price (timestamp = 0)
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        0, // timestamp (stale)
    );

    // Create stale SUI price (also timestamp = 0)
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        0, // timestamp (stale)
    );

    // Function should abort when both prices are stale (> 60 seconds old)
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EInvalidPriceFeedIdentifier)]
fun deep_price_id_is_wrong() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with wrong price ID but valid parameters
    let deep_price = new_price_info_object(
        &mut scenario,
        create_custom_price_id(), // Wrong price ID
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Create valid SUI price
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Function should abort when DEEP price ID is wrong
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EInvalidPriceFeedIdentifier)]
fun sui_price_id_is_wrong() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create valid DEEP price
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Create SUI price with wrong price ID but valid parameters
    let sui_price = new_price_info_object(
        &mut scenario,
        create_custom_price_id(),
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Function should abort when SUI price ID is wrong
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EInvalidPriceFeedIdentifier)]
fun both_price_ids_are_wrong() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create both prices with wrong IDs but valid parameters
    let deep_price = new_price_info_object(
        &mut scenario,
        create_custom_price_id(),
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    let sui_price = new_price_info_object(
        &mut scenario,
        create_custom_price_id(),
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Function should abort when both price IDs are wrong
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EInvalidPriceFeedIdentifier)]
fun max_deep_price_and_invalid_sui_id() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with maximum i64 value but valid parameters
    let deep_price = new_deep_price_object(
        &mut scenario,
        MAX_POSITIVE_MAGNITUDE, // max i64 positive value
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Create SUI price with wrong ID
    let sui_price = new_price_info_object(
        &mut scenario,
        create_custom_price_id(),
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Function should abort when SUI price ID is wrong, even with valid max DEEP price
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EInvalidPriceFeedIdentifier)]
fun max_sui_price_and_invalid_deep_id() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with wrong ID
    let deep_price = new_price_info_object(
        &mut scenario,
        create_custom_price_id(),
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Create SUI price with maximum i64 value but valid parameters
    let sui_price = new_sui_price_object(
        &mut scenario,
        MAX_POSITIVE_MAGNITUDE, // max i64 positive value
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Function should abort when DEEP price ID is wrong, even with valid max SUI price
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EStalePrice)]
fun stale_deep_price_and_sui_price_out_of_confidence() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    // Set current time to just over max staleness (60 seconds)
    let current_time = 61_000; // 61 seconds in milliseconds
    clock::set_for_testing(&mut clock, current_time);

    // Create stale DEEP price
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        0, // timestamp (stale)
    );

    // Create SUI price with high confidence interval
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        11, // confidence (11 * 10 > 100, so price is out of confidence)
        8, // exponent
        true, // exponent is negative
        current_time, // timestamp (fresh)
    );

    // Function should abort when DEEP price is stale (checked first)
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EPriceConfidenceExceedsThreshold)]
fun stale_sui_price_and_deep_price_out_of_confidence() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    // Set current time to just over max staleness (60 seconds)
    let current_time = 61_000; // 61 seconds in milliseconds
    clock::set_for_testing(&mut clock, current_time);

    // Create DEEP price with high confidence interval
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        11, // confidence (11 * 10 > 100, so price is out of confidence)
        8, // exponent
        true, // exponent is negative
        current_time, // timestamp (fresh)
    );

    // Create stale SUI price
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        0, // timestamp (stale)
    );

    // Function should abort when DEEP price confidence exceeds threshold (checked first)
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure]
fun deep_price_expo_is_positive() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with positive exponent (should cause abort)
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        false, // exponent is positive (this will cause the abort)
        current_time, // use current time to ensure price is fresh
    );

    // Create valid SUI price
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Function should abort because DEEP price exponent is positive
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure]
fun sui_price_expo_is_positive() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create valid DEEP price
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time, // use current time to ensure price is fresh
    );

    // Create SUI price with positive exponent (should cause abort)
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        false, // exponent is positive (this will cause the abort)
        current_time, // use current time to ensure price is fresh
    );

    // Function should abort because SUI price exponent is positive
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure]
fun both_price_expos_are_positive() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with positive exponent
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        false, // exponent is positive (this will cause abort)
        current_time, // use current time to ensure price is fresh
    );

    // Create SUI price also with positive exponent
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        false, // exponent is positive (this would also cause abort)
        current_time, // use current time to ensure price is fresh
    );

    // Function should abort because both price exponents are positive
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure]
fun multiplier_calculation_overflows() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with small exponent magnitude
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        1, // small exponent magnitude
        true, // exponent is negative
        current_time,
    );

    // Create SUI price with very large exponent magnitude
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        60, // large exponent magnitude
        true, // exponent is negative
        current_time,
    );

    // Function should abort due to overflow in multiplier calculation
    // When sui_expo.magnitude = 60 and deep_expo.magnitude = 1 (both negative)
    // sui_expo + 3 >= deep_expo will be: 60 + 3 >= 1, which is true
    // So decimal_adjustment = sui_expo + 3 - deep_expo = 60 + 3 - 1 = 62
    // This will make multiplier = 10^62 which should overflow
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure]
fun deep_price_numerator_overflow() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with very large magnitude
    let deep_price = new_deep_price_object(
        &mut scenario,
        MAX_POSITIVE_MAGNITUDE, // max i64 value for price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        1, // small exponent
        true, // exponent is negative
        current_time,
    );

    // Create SUI price with small magnitude but large negative exponent
    // This will make multiplier large, causing overflow when multiplied with deep_price_mag
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // small price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        10, // large exponent
        true, // exponent is negative
        current_time,
    );

    // Function should abort due to overflow in deep_price_mag * multiplier
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure]
fun sui_price_denominator_overflow() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with large negative exponent
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // small price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        10, // large exponent
        true, // exponent is negative
        current_time,
    );

    // Create SUI price with very large magnitude
    let sui_price = new_sui_price_object(
        &mut scenario,
        MAX_POSITIVE_MAGNITUDE, // max i64 value for price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        1, // small exponent
        true, // exponent is negative
        current_time,
    );

    // Function should abort due to overflow in sui_price_mag * multiplier
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EZeroPriceMagnitude)]
fun deep_price_is_zero() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with zero magnitude
    let deep_price = new_deep_price_object(
        &mut scenario,
        0, // zero price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Create valid SUI price
    let sui_price = new_sui_price_object(
        &mut scenario,
        100, // normal price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Function should abort when DEEP price is zero
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EZeroPriceMagnitude)]
fun sui_price_is_zero() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create valid DEEP price
    let deep_price = new_deep_price_object(
        &mut scenario,
        100, // normal price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Create SUI price with zero magnitude
    let sui_price = new_sui_price_object(
        &mut scenario,
        0, // zero price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Function should abort when SUI price is zero
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = EZeroPriceMagnitude)]
fun both_prices_are_zero() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with zero magnitude
    let deep_price = new_deep_price_object(
        &mut scenario,
        0, // zero price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Create SUI price also with zero magnitude
    let sui_price = new_sui_price_object(
        &mut scenario,
        0, // zero price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Function should abort when DEEP price is zero (checked first)
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached due to abort, but included for completeness
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test]
fun deep_price_is_very_small() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with very small magnitude
    let deep_price = new_deep_price_object(
        &mut scenario,
        1, // smallest possible non-zero magnitude
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Create normal SUI price
    let sui_price = new_sui_price_object(
        &mut scenario,
        1000, // normal price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Function should handle small DEEP price correctly
    let result = get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);
    assert_eq!(result, 1_000_000_000);

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test]
fun sui_price_is_very_small() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create normal DEEP price
    let deep_price = new_deep_price_object(
        &mut scenario,
        1000, // normal price magnitude
        false, // price is positive
        5, // confidence (within valid range)
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Create SUI price with very small magnitude
    let sui_price = new_sui_price_object(
        &mut scenario,
        1, // smallest possible non-zero magnitude
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Function should handle small SUI price correctly
    let result = get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);
    assert_eq!(result, 1_000_000_000_000_000);

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test]
fun both_prices_are_very_small() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with very small magnitude
    let deep_price = new_deep_price_object(
        &mut scenario,
        1, // smallest possible non-zero magnitude
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Create SUI price also with very small magnitude
    let sui_price = new_sui_price_object(
        &mut scenario,
        1, // smallest possible non-zero magnitude
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Function should handle both small prices correctly
    let result = get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);
    assert_eq!(result, 1_000_000_000_000);

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test]
fun small_price_with_large_exponent_difference() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with small magnitude and small exponent
    let deep_price = new_deep_price_object(
        &mut scenario,
        1, // smallest possible non-zero magnitude
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        1, // small exponent
        true, // exponent is negative
        current_time,
    );

    // Create SUI price with small magnitude but large exponent
    let sui_price = new_sui_price_object(
        &mut scenario,
        1, // smallest possible non-zero magnitude
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        7, // large exponent
        true, // exponent is negative
        current_time,
    );

    // Function should handle extreme exponent differences with small prices correctly
    let result = get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);
    assert_eq!(result, 1_000_000_000_000_000_000);

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test]
fun deep_price_is_huge() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price with large but safe magnitude
    let deep_price = new_deep_price_object(
        &mut scenario,
        1_000_000_000_000, // 1 trillion
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // matching exponent to avoid large multiplier
        true, // exponent is negative
        current_time,
    );

    // Create normal SUI price
    let sui_price = new_sui_price_object(
        &mut scenario,
        1_000_000_000, // 1 billion
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // matching exponent to avoid large multiplier
        true, // exponent is negative
        current_time,
    );

    // Function should handle large DEEP price correctly
    let result = get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);
    assert_eq!(result, 1_000_000_000_000_000); // Should be 1000 with 12 decimals

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test]
fun sui_price_is_huge() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create normal DEEP price
    let deep_price = new_deep_price_object(
        &mut scenario,
        1_000_000_000, // 1 billion
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // matching exponent to avoid large multiplier
        true, // exponent is negative
        current_time,
    );

    // Create SUI price with large but safe magnitude
    let sui_price = new_sui_price_object(
        &mut scenario,
        1_000_000_000_000, // 1 trillion
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // matching exponent to avoid large multiplier
        true, // exponent is negative
        current_time,
    );

    // Function should handle large SUI price correctly
    let result = get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);
    assert_eq!(result, 1_000_000_000); // Should be 0.001 with 12 decimals

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test]
fun both_prices_are_huge() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create both prices with large but safe magnitudes
    let deep_price = new_deep_price_object(
        &mut scenario,
        1_000_000_000_000, // 1 trillion
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // matching exponent to avoid large multiplier
        true, // exponent is negative
        current_time,
    );

    let sui_price = new_sui_price_object(
        &mut scenario,
        1_000_000_000_000, // 1 trillion
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // matching exponent to avoid large multiplier
        true, // exponent is negative
        current_time,
    );

    // Function should handle both large prices correctly
    let result = get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);
    assert_eq!(result, 1_000_000_000_000); // Should be 1 with 12 decimals since prices are equal

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test]
fun huge_price_with_different_exponents() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create prices with large but safe magnitudes and different exponents
    let deep_price = new_deep_price_object(
        &mut scenario,
        1_000_000_000_000, // 1 trillion
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        9, // larger exponent
        true, // exponent is negative
        current_time,
    );

    let sui_price = new_sui_price_object(
        &mut scenario,
        1_000_000_000_000, // 1 trillion
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        7, // smaller exponent
        true, // exponent is negative
        current_time,
    );

    // Function should handle large prices with different exponents correctly
    let result = get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);
    assert_eq!(result, 10_000_000_000); // Should be 0.01 with 12 decimals due to exponent difference

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure]
fun deep_price_expo_is_zero() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // This will abort because i64::new forces negative = false when magnitude = 0
    let deep_price = new_deep_price_object(
        &mut scenario,
        1_000_000, // 1 million
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        0, // zero exponent
        true, // exponent is negative - this will cause abort due to i64::new behavior
        current_time,
    );

    let sui_price = new_sui_price_object(
        &mut scenario,
        1_000_000, // 1 million
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // normal exponent
        true, // exponent is negative
        current_time,
    );

    // We won't reach this point due to the abort
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure]
fun sui_price_expo_is_zero() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    let deep_price = new_deep_price_object(
        &mut scenario,
        1_000_000, // 1 million
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // normal exponent
        true, // exponent is negative
        current_time,
    );

    // This will abort because i64::new forces negative = false when magnitude = 0
    let sui_price = new_sui_price_object(
        &mut scenario,
        1_000_000, // 1 million
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        0, // zero exponent
        true, // exponent is negative - this will cause abort due to i64::new behavior
        current_time,
    );

    // We won't reach this point due to the abort
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test, expected_failure]
fun both_price_expos_are_zero() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // This will abort because i64::new forces negative = false when magnitude = 0
    let deep_price = new_deep_price_object(
        &mut scenario,
        1_000_000, // 1 million
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        0, // zero exponent
        true, // exponent is negative - this will cause abort due to i64::new behavior
        current_time,
    );

    // This would also abort if we reached it
    let sui_price = new_sui_price_object(
        &mut scenario,
        1_000_000, // 1 million
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        0, // zero exponent
        true, // exponent is negative - this will cause abort due to i64::new behavior
        current_time,
    );

    // We won't reach this point due to the abort
    get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);

    // Cleanup won't be reached
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test]
fun division_with_uneven_numbers() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price that will result in uneven division
    let deep_price = new_deep_price_object(
        &mut scenario,
        3, // Using 3 to force uneven division
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Create SUI price that's not cleanly divisible
    let sui_price = new_sui_price_object(
        &mut scenario,
        10, // This will make DEEP/SUI = 0.3
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Function should handle division with proper precision
    let result = get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);
    assert_eq!(result, 300_000_000_000); // Should be 0.3 with 12 decimals

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test]
fun division_with_large_precision_loss() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price that will cause significant digit loss
    let deep_price = new_deep_price_object(
        &mut scenario,
        1, // Small numerator
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Create SUI price that will cause many decimal places
    let sui_price = new_sui_price_object(
        &mut scenario,
        7, // This will make DEEP/SUI ≈ 0.142857...
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Function should handle recurring decimal truncation
    let result = get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);
    assert_eq!(result, 142_857_142_857); // Should be 0.142857142857 with 12 decimals

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test]
fun division_with_prime_numbers() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let current_time = clock::timestamp_ms(&clock);

    // Create DEEP price using a prime number
    let deep_price = new_deep_price_object(
        &mut scenario,
        17, // Prime number
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Create SUI price using another prime number
    let sui_price = new_sui_price_object(
        &mut scenario,
        23, // Prime number
        false, // price is positive
        0, // small confidence to ensure it's within valid range
        8, // exponent
        true, // exponent is negative
        current_time,
    );

    // Function should handle division of prime numbers correctly
    let result = get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);
    assert_eq!(result, 739_130_434_782); // Should be 0.739130434782 with 12 decimals

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test]
fun real_world_price_ratio() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    // Using real timestamps from SDK example
    clock::set_for_testing(&mut clock, 1748854989);

    // Create DEEP price using real market data
    let deep_price = new_deep_price_object(
        &mut scenario,
        14909488, // Real DEEP price from SDK (≈0.14909488 USD)
        false, // price is positive
        18480, // Real confidence value
        8, // Real exponent
        true, // exponent is negative
        1748855041, // Real timestamp
    );

    // Create SUI price using real market data
    let sui_price = new_sui_price_object(
        &mut scenario,
        330187720, // Real SUI price from SDK (≈3.30187720 USD)
        false, // price is positive
        294671, // Real confidence value
        8, // Real exponent
        true, // exponent is negative
        1748854989, // Real timestamp
    );

    // Calculate DEEP/SUI ratio
    // Expected calculation:
    // DEEP price in USD / SUI price in USD = 0.14909488 / 3.30187720 = 0.045154...
    let result = get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);
    assert_eq!(result, 45_154_580_551); // Should be 0.045154580551 with 12 decimals

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    test_scenario::end(scenario);
}

#[test_only]
fun new_deep_price_object(
    scenario: &mut Scenario,
    price_magnitude: u64,
    price_mag_is_negative: bool,
    confidence: u64,
    price_expo: u64,
    price_expo_is_negative: bool,
    timestamp: u64,
): PriceInfoObject {
    let price_id = oracle::get_deep_price_fee_id();
    new_price_info_object(
        scenario,
        price_id,
        price_magnitude,
        price_mag_is_negative,
        confidence,
        price_expo,
        price_expo_is_negative,
        timestamp,
    )
}

#[test_only]
fun new_sui_price_object(
    scenario: &mut Scenario,
    price_magnitude: u64,
    price_mag_is_negative: bool,
    confidence: u64,
    price_expo: u64,
    price_expo_is_negative: bool,
    timestamp: u64,
): PriceInfoObject {
    let price_id = oracle::get_sui_price_fee_id();
    new_price_info_object(
        scenario,
        price_id,
        price_magnitude,
        price_mag_is_negative,
        confidence,
        price_expo,
        price_expo_is_negative,
        timestamp,
    )
}

#[test_only]
fun new_price_info_object(
    scenario: &mut Scenario,
    price_id: vector<u8>,
    price_magnitude: u64,
    price_mag_is_negative: bool,
    confidence: u64,
    price_expo: u64,
    price_expo_is_negative: bool,
    timestamp: u64,
): PriceInfoObject {
    price_info::new_price_info_object_for_testing(
        price_info::new_price_info(
            0,
            0,
            price_feed::new(
                price_identifier::from_byte_vec(price_id),
                // Regular price
                price::new(
                    i64::new(price_magnitude, price_mag_is_negative),
                    confidence,
                    i64::new(price_expo, price_expo_is_negative),
                    timestamp,
                ),
                // We use only regular price so no need to set the ema price
                price::new(
                    i64::new(price_magnitude, price_mag_is_negative),
                    confidence,
                    i64::new(price_expo, price_expo_is_negative),
                    timestamp,
                ),
            ),
        ),
        test_scenario::ctx(scenario),
    )
}

#[test_only]
fun create_custom_price_id(): vector<u8> {
    let mut v = vector::empty<u8>();
    let mut i = 0;
    while (i < 32) {
        vector::push_back(&mut v, 1);
        i = i + 1;
    };
    v
}

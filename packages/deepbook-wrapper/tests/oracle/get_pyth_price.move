#[test_only]
module deepbook_wrapper::get_pyth_price_tests;

use deepbook_wrapper::oracle::get_pyth_price;
use pyth::i64;
use pyth::price;
use pyth::price_feed;
use pyth::price_identifier::{Self, PriceIdentifier};
use pyth::price_info;
use std::unit_test::assert_eq;
use sui::clock;
use sui::test_scenario;

#[test_only]
fun example_price_identifier(): PriceIdentifier {
    let mut v = vector::empty<u8>();

    let mut i = 0;
    while (i < 32) {
        vector::push_back(&mut v, 0);
        i = i + 1;
    };

    price_identifier::from_byte_vec(v)
}

#[test]
fun happy() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let price_info_object = price_info::new_price_info_object_for_testing(
        price_info::new_price_info(
            0,
            0,
            price_feed::new(
                example_price_identifier(),
                price::new(
                    i64::new(8, false),
                    0,
                    i64::new(4, true),
                    0,
                ),
                price::new(
                    i64::new(8, false),
                    0,
                    i64::new(5, false),
                    0,
                ),
            ),
        ),
        test_scenario::ctx(&mut scenario),
    );

    let (mut price_opt, price_identifier) = get_pyth_price(
        &price_info_object,
        &clock,
    );
    let price = price_opt.extract();
    let price_mag = price.get_price().get_magnitude_if_positive();

    assert_eq!(price_mag, 8);
    assert_eq!(price_identifier, example_price_identifier());

    price_info::destroy(price_info_object);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun confidence_interval_exceeded() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let price_info_object = price_info::new_price_info_object_for_testing(
        price_info::new_price_info(
            0,
            0,
            price_feed::new(
                example_price_identifier(),
                price::new(
                    i64::new(100, false),
                    11, // 11%
                    i64::new(4, true),
                    0,
                ),
                price::new(
                    i64::new(100, false),
                    10,
                    i64::new(5, false),
                    0,
                ),
            ),
        ),
        test_scenario::ctx(&mut scenario),
    );

    let (price_opt, price_identifier) = get_pyth_price(
        &price_info_object,
        &clock,
    );

    // Confidence interval higher than 10% of the price
    assert_eq!(price_opt, option::none());
    assert_eq!(price_identifier, example_price_identifier());

    price_info::destroy(price_info_object);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun price_is_stale() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 61_000); // 61 seconds passed, max staleness is 60 seconds

    let price_info_object = price_info::new_price_info_object_for_testing(
        price_info::new_price_info(
            0,
            0,
            price_feed::new(
                example_price_identifier(),
                price::new(
                    i64::new(8, false),
                    0,
                    i64::new(4, true),
                    0,
                ),
                price::new(
                    i64::new(100, false),
                    0,
                    i64::new(5, false),
                    0,
                ),
            ),
        ),
        test_scenario::ctx(&mut scenario),
    );

    let (price_opt, price_identifier) = get_pyth_price(
        &price_info_object,
        &clock,
    );

    assert_eq!(price_opt, option::none());
    assert_eq!(price_identifier, example_price_identifier());

    price_info::destroy(price_info_object);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test, expected_failure]
fun price_magnitude_is_negative() {
    let owner = @0x26;
    let mut scenario = test_scenario::begin(owner);
    let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let price_info_object = price_info::new_price_info_object_for_testing(
        price_info::new_price_info(
            0,
            0,
            price_feed::new(
                example_price_identifier(),
                price::new(
                    i64::new(8, true), // negative magnitude
                    0,
                    i64::new(4, true),
                    0,
                ),
                price::new(
                    i64::new(100, false),
                    0,
                    i64::new(5, false),
                    0,
                ),
            ),
        ),
        test_scenario::ctx(&mut scenario),
    );

    get_pyth_price(&price_info_object, &clock);

    price_info::destroy(price_info_object);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

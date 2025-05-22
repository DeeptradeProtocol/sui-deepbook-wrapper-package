#[test_only]
module deepbook_wrapper::plan_fee_collection_tests;

use deepbook_wrapper::order;
use std::unit_test::assert_eq;

/// Test that planning fee collection with zero fee returns zeros
#[test]
fun plan_fee_collection_zero_fee() {
    let (from_wallet, from_bm) = order::plan_fee_collection(
        0, // fee_amount
        1000, // available_in_wallet
        1000, // available_in_bm
    );
    assert_eq!(from_wallet, 0);
    assert_eq!(from_bm, 0);
}

/// Test when BM has insufficient funds and wallet is empty
#[test, expected_failure]
fun plan_fee_collection_bm_insufficient() {
    let fee_amount = 1000;
    let available_in_bm = 500;
    order::plan_fee_collection(
        fee_amount, // fee_amount
        0, // available_in_wallet (empty)
        available_in_bm, // available_in_bm (insufficient)
    );
}

/// Test when BM has exact amount needed and wallet is empty
#[test]
fun plan_fee_collection_bm_exact() {
    let fee_amount = 1000;
    let (from_wallet, from_bm) = order::plan_fee_collection(
        fee_amount, // fee_amount
        0, // available_in_wallet (empty)
        fee_amount, // available_in_bm (exact amount)
    );
    assert_eq!(from_wallet, 0);
    assert_eq!(from_bm, fee_amount);
}

/// Test when BM has excess funds and wallet is empty
#[test]
fun plan_fee_collection_bm_excess() {
    let fee_amount = 1000;
    let (from_wallet, from_bm) = order::plan_fee_collection(
        fee_amount, // fee_amount
        0, // available_in_wallet (empty)
        fee_amount * 2, // available_in_bm (double the needed amount)
    );
    assert_eq!(from_wallet, 0);
    assert_eq!(from_bm, fee_amount);
}

/// Test when wallet has insufficient funds and BM is empty
#[test, expected_failure]
fun plan_fee_collection_wallet_insufficient() {
    let fee_amount = 1000;
    let available_in_wallet = 500;
    order::plan_fee_collection(
        fee_amount, // fee_amount
        available_in_wallet, // available_in_wallet (insufficient)
        0, // available_in_bm (empty)
    );
}

/// Test when wallet has exact amount needed and BM is empty
#[test]
fun plan_fee_collection_wallet_exact() {
    let fee_amount = 1000;
    let (from_wallet, from_bm) = order::plan_fee_collection(
        fee_amount, // fee_amount
        fee_amount, // available_in_wallet (exact amount)
        0, // available_in_bm (empty)
    );
    assert_eq!(from_wallet, fee_amount);
    assert_eq!(from_bm, 0);
}

/// Test when wallet has excess funds and BM is empty
#[test]
fun plan_fee_collection_wallet_excess() {
    let fee_amount = 1000;
    let (from_wallet, from_bm) = order::plan_fee_collection(
        fee_amount, // fee_amount
        fee_amount * 2, // available_in_wallet (double the needed amount)
        0, // available_in_bm (empty)
    );
    assert_eq!(from_wallet, fee_amount);
    assert_eq!(from_bm, 0);
}

/// Test when both sources have insufficient funds
#[test, expected_failure]
fun plan_fee_collection_split_both_insufficient() {
    let fee_amount = 1000;
    order::plan_fee_collection(
        fee_amount, // fee_amount
        400, // available_in_wallet (insufficient)
        500, // available_in_bm (insufficient)
    );
}

/// Test when sum of both sources exactly equals needed amount
#[test]
fun plan_fee_collection_split_exact_sum() {
    let fee_amount = 1000;
    let bm_amount = 600;
    let wallet_amount = fee_amount - bm_amount;

    let (from_wallet, from_bm) = order::plan_fee_collection(
        fee_amount, // fee_amount
        wallet_amount, // available_in_wallet (partial amount)
        bm_amount, // available_in_bm (partial amount)
    );
    assert_eq!(from_wallet, wallet_amount);
    assert_eq!(from_bm, bm_amount);
    assert_eq!(from_wallet + from_bm, fee_amount);
}

/// Test when BM has excess funds while wallet also has funds
#[test]
fun plan_fee_collection_split_bm_excess() {
    let fee_amount = 1000;
    let (from_wallet, from_bm) = order::plan_fee_collection(
        fee_amount, // fee_amount
        500, // available_in_wallet (has funds but not needed)
        fee_amount * 2, // available_in_bm (more than needed)
    );
    assert_eq!(from_wallet, 0);
    assert_eq!(from_bm, fee_amount);
}

/// Test when wallet has excess funds while BM also has funds
#[test]
fun plan_fee_collection_split_wallet_excess() {
    let fee_amount = 1000;
    let (from_wallet, from_bm) = order::plan_fee_collection(
        fee_amount, // fee_amount
        fee_amount * 2, // available_in_wallet (more than needed)
        500, // available_in_bm (has funds but not needed)
    );
    // Should still take from BM first even though wallet has excess
    assert_eq!(from_wallet, fee_amount - 500);
    assert_eq!(from_bm, 500);
}

#[test_only]
module deepbook_wrapper::calculate_order_taker_maker_ratio_tests;

use deepbook::constants::{live, partially_filled, filled, canceled, expired};
use deepbook_wrapper::helper::{
    calculate_order_taker_maker_ratio,
    EZeroOriginalQuantity,
    EExecutedQuantityExceedsOriginal
};
use std::unit_test::assert_eq;

/// Constants for common test values
const SCALING: u64 = 1_000_000_000; // 10^9 (billionths)

// Common order quantities for testing
const QUANTITY_MEDIUM: u64 = 1_000_000_000; // Medium order

// ===== Edge Cases =====

#[test]
/// Test when executed_quantity is zero - should return pure maker ratio
fun executed_quantity_zero() {
    // LIVE order with no execution - should be 100% maker
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        QUANTITY_MEDIUM, // original_quantity
        0, // executed_quantity
        live(), // order_status
    );
    assert_eq!(taker_ratio, 0); // 0% taker
    assert_eq!(maker_ratio, SCALING); // 100% maker

    // PARTIALLY_FILLED order with no execution - should be 100% maker
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        QUANTITY_MEDIUM, // original_quantity
        0, // executed_quantity
        partially_filled(), // order_status
    );
    assert_eq!(taker_ratio, 0); // 0% taker
    assert_eq!(maker_ratio, SCALING); // 100% maker

    // FILLED order with no execution - should be 100% taker (no maker part)
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        QUANTITY_MEDIUM, // original_quantity
        0, // executed_quantity
        filled(), // order_status
    );
    assert_eq!(taker_ratio, 0); // 0% taker
    assert_eq!(maker_ratio, 0); // 0% maker (filled status = no maker part)
}

#[test]
/// Test when executed_quantity equals original_quantity - should return pure taker ratio
fun executed_quantity_equals_original() {
    // Test with different order statuses - all should have no maker part when fully executed
    let statuses = vector[live(), partially_filled(), filled(), canceled(), expired()];

    let mut i = 0;
    while (i < vector::length(&statuses)) {
        let status = *vector::borrow(&statuses, i);
        let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
            QUANTITY_MEDIUM, // original_quantity
            QUANTITY_MEDIUM, // executed_quantity (fully executed)
            status, // order_status
        );
        assert_eq!(taker_ratio, SCALING); // 100% taker
        assert_eq!(maker_ratio, 0); // 0% maker (fully executed = no maker part)
        i = i + 1;
    };
}

// ===== Boundary Conditions =====

#[test, expected_failure(abort_code = EZeroOriginalQuantity)]
/// Test when original_quantity is zero - should abort
fun original_quantity_zero() {
    calculate_order_taker_maker_ratio(
        0, // original_quantity (zero)
        0, // executed_quantity
        live(), // order_status
    );
}

#[test, expected_failure(abort_code = EExecutedQuantityExceedsOriginal)]
/// Test when executed_quantity exceeds original_quantity - should abort
fun executed_quantity_exceeds_original() {
    calculate_order_taker_maker_ratio(
        QUANTITY_MEDIUM, // original_quantity
        QUANTITY_MEDIUM + 1, // executed_quantity (exceeds original)
        live(), // order_status
    );
}

// ===== Order Status Cases =====

#[test]
/// Test LIVE order status with various execution ratios
fun live_order_status() {
    let status = live();
    let original = QUANTITY_MEDIUM;

    // 25% executed - should have both taker and maker parts
    let executed = original / 4;
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        original,
        executed,
        status,
    );
    assert_eq!(taker_ratio, 250_000_000); // 25%
    assert_eq!(maker_ratio, 750_000_000); // 75%
    assert_eq!(taker_ratio + maker_ratio, SCALING); // Should sum to 100%

    // 50% executed - should have both taker and maker parts
    let executed = original / 2;
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        original,
        executed,
        status,
    );
    assert_eq!(taker_ratio, 500_000_000); // 50%
    assert_eq!(maker_ratio, 500_000_000); // 50%
    assert_eq!(taker_ratio + maker_ratio, SCALING); // Should sum to 100%

    // 75% executed - should have both taker and maker parts
    let executed = original * 3 / 4;
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        original,
        executed,
        status,
    );
    assert_eq!(taker_ratio, 750_000_000); // 75%
    assert_eq!(maker_ratio, 250_000_000); // 25%
    assert_eq!(taker_ratio + maker_ratio, SCALING); // Should sum to 100%
}

#[test]
/// Test PARTIALLY_FILLED order status with various execution ratios
fun partially_filled_order_status() {
    let status = partially_filled();
    let original = QUANTITY_MEDIUM;

    // 25% executed - should have both taker and maker parts
    let executed = original / 4;
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        original,
        executed,
        status,
    );
    assert_eq!(taker_ratio, 250_000_000); // 25%
    assert_eq!(maker_ratio, 750_000_000); // 75%
    assert_eq!(taker_ratio + maker_ratio, SCALING); // Should sum to 100%

    // 90% executed - should have both taker and maker parts
    let executed = original * 9 / 10;
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        original,
        executed,
        status,
    );
    assert_eq!(taker_ratio, 900_000_000); // 90%
    assert_eq!(maker_ratio, 100_000_000); // 10%
    assert_eq!(taker_ratio + maker_ratio, SCALING); // Should sum to 100%
}

#[test]
/// Test FILLED order status - should never have maker part
fun filled_order_status() {
    let status = filled();
    let original = QUANTITY_MEDIUM;

    // Test various execution ratios - all should have no maker part
    let execution_ratios = vector[25, 50, 75, 90, 100];

    let mut i = 0;
    while (i < vector::length(&execution_ratios)) {
        let ratio = *vector::borrow(&execution_ratios, i);
        let executed = original * ratio / 100;
        let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
            original,
            executed,
            status,
        );

        // Expected taker ratio based on execution
        let expected_taker = (ratio as u64) * 10_000_000; // Convert to billionths
        assert_eq!(taker_ratio, expected_taker);
        assert_eq!(maker_ratio, 0); // FILLED status = no maker part
        i = i + 1;
    };
}

#[test]
/// Test CANCELED order status - should never have maker part
fun canceled_order_status() {
    let status = canceled();
    let original = QUANTITY_MEDIUM;

    // Test various execution ratios - all should have no maker part
    let execution_ratios = vector[0, 25, 50, 75];

    let mut i = 0;
    while (i < vector::length(&execution_ratios)) {
        let ratio = *vector::borrow(&execution_ratios, i);
        let executed = original * ratio / 100;
        let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
            original,
            executed,
            status,
        );

        // Expected taker ratio based on execution
        let expected_taker = (ratio as u64) * 10_000_000; // Convert to billionths
        assert_eq!(taker_ratio, expected_taker);
        assert_eq!(maker_ratio, 0); // CANCELED status = no maker part
        i = i + 1;
    };
}

#[test]
/// Test EXPIRED order status - should never have maker part
fun expired_order_status() {
    let status = expired();
    let original = QUANTITY_MEDIUM;

    // Test various execution ratios - all should have no maker part
    let execution_ratios = vector[0, 25, 50, 75];

    let mut i = 0;
    while (i < vector::length(&execution_ratios)) {
        let ratio = *vector::borrow(&execution_ratios, i);
        let executed = original * ratio / 100;
        let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
            original,
            executed,
            status,
        );

        // Expected taker ratio based on execution
        let expected_taker = (ratio as u64) * 10_000_000; // Convert to billionths
        assert_eq!(taker_ratio, expected_taker);
        assert_eq!(maker_ratio, 0); // EXPIRED status = no maker part
        i = i + 1;
    };
}

// ===== Math Precision Tests =====

#[test]
/// Test with small quantities to verify integer division precision
fun small_quantities_precision() {
    // Test with amounts that could cause precision issues
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        3, // original_quantity
        1, // executed_quantity
        live(), // order_status
    );
    // Expected: 1/3 = 33.333...% taker, 66.666...% maker
    assert_eq!(taker_ratio, 333_333_333); // Rounded down from 333.333...%
    assert_eq!(maker_ratio, 666_666_667); // 100% - taker_ratio
    assert_eq!(taker_ratio + maker_ratio, SCALING); // Should sum to 100%

    // Test with very small values
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        7, // original_quantity
        2, // executed_quantity
        partially_filled(), // order_status
    );
    // Expected: 2/7 = 28.571...% taker, 71.428...% maker
    assert_eq!(taker_ratio, 285_714_285); // Rounded down from 285.714...%
    assert_eq!(maker_ratio, 714_285_715); // 100% - taker_ratio
    assert_eq!(taker_ratio + maker_ratio, SCALING); // Should sum to 100%
}

#[test]
/// Test with large quantities to ensure no overflow
fun large_quantities() {
    // Test with large values close to u64 limits
    let large_quantity = 18_000_000_000_000_000_000; // Close to max u64
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        large_quantity, // original_quantity
        large_quantity / 2, // executed_quantity (50%)
        live(), // order_status
    );
    // Expected: 50% taker, 50% maker
    assert_eq!(taker_ratio, 500_000_000); // 50%
    assert_eq!(maker_ratio, 500_000_000); // 50%
    assert_eq!(taker_ratio + maker_ratio, SCALING); // Should sum to 100%

    // Test with maximum possible execution
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        large_quantity, // original_quantity
        large_quantity - 1, // executed_quantity (almost fully executed)
        live(), // order_status
    );
    // Expected: ~100% taker, ~0% maker
    assert_eq!(taker_ratio, 999_999_999); // Almost 100%
    assert_eq!(maker_ratio, 1); // Almost 0%
    assert_eq!(taker_ratio + maker_ratio, SCALING); // Should sum to 100%
}

// ===== Formula Verification =====

#[test]
/// Test that taker + maker ratios always sum to 100% for orders with maker parts
fun ratio_sum_verification() {
    let original = QUANTITY_MEDIUM;
    let maker_statuses = vector[live(), partially_filled()];

    let mut status_i = 0;
    while (status_i < vector::length(&maker_statuses)) {
        let status = *vector::borrow(&maker_statuses, status_i);

        // Test various execution percentages
        let execution_percentages = vector[10, 25, 33, 50, 66, 75, 90, 99];

        let mut exec_i = 0;
        while (exec_i < vector::length(&execution_percentages)) {
            let percentage = *vector::borrow(&execution_percentages, exec_i);
            let executed = original * percentage / 100;

            let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
                original,
                executed,
                status,
            );

            // For maker orders, ratios should sum to 100%
            assert_eq!(taker_ratio + maker_ratio, SCALING);

            exec_i = exec_i + 1;
        };

        status_i = status_i + 1;
    };
}

#[test]
/// Test taker ratio accuracy across various execution percentages
fun taker_ratio_accuracy() {
    let original = 10_000_000; // Use a round number for easier calculation
    let status = live();

    // Test specific percentages - using separate vectors since Move doesn't support tuple vectors
    let executed_quantities = vector[
        1_000_000, // 10%
        2_000_000, // 20%
        3_000_000, // 30%
        4_000_000, // 40%
        5_000_000, // 50%
        6_000_000, // 60%
        7_000_000, // 70%
        8_000_000, // 80%
        9_000_000, // 90%
    ];

    let expected_taker_ratios = vector[
        100_000_000, // 10%
        200_000_000, // 20%
        300_000_000, // 30%
        400_000_000, // 40%
        500_000_000, // 50%
        600_000_000, // 60%
        700_000_000, // 70%
        800_000_000, // 80%
        900_000_000, // 90%
    ];

    let mut i = 0;
    while (i < vector::length(&executed_quantities)) {
        let executed = *vector::borrow(&executed_quantities, i);
        let expected_taker = *vector::borrow(&expected_taker_ratios, i);
        let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
            original,
            executed,
            status,
        );

        assert_eq!(taker_ratio, expected_taker);
        assert_eq!(maker_ratio, SCALING - expected_taker);

        i = i + 1;
    };
}

#[test]
/// Test that maker ratio is zero for non-maker statuses
fun maker_ratio_zero_for_non_maker_statuses() {
    let original = QUANTITY_MEDIUM;
    let non_maker_statuses = vector[filled(), canceled(), expired()];

    let mut status_i = 0;
    while (status_i < vector::length(&non_maker_statuses)) {
        let status = *vector::borrow(&non_maker_statuses, status_i);

        // Test various execution percentages
        let execution_percentages = vector[0, 25, 50, 75, 100];

        let mut exec_i = 0;
        while (exec_i < vector::length(&execution_percentages)) {
            let percentage = *vector::borrow(&execution_percentages, exec_i);
            let executed = original * percentage / 100;

            let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
                original,
                executed,
                status,
            );

            // For non-maker statuses, maker ratio should always be 0
            assert_eq!(maker_ratio, 0);

            // Taker ratio should match execution percentage
            let expected_taker = (percentage as u64) * 10_000_000; // Convert to billionths
            assert_eq!(taker_ratio, expected_taker);

            exec_i = exec_i + 1;
        };

        status_i = status_i + 1;
    };
}

// ===== Comprehensive Integration Tests =====

#[test]
/// Test all combinations of execution ratios and order statuses
fun comprehensive_combinations() {
    let original = 1_000_000_000; // Use large round number
    let execution_ratios = vector[0, 25, 50, 75, 100];
    let all_statuses = vector[live(), partially_filled(), filled(), canceled(), expired()];

    let mut status_i = 0;
    while (status_i < vector::length(&all_statuses)) {
        let status = *vector::borrow(&all_statuses, status_i);

        let mut exec_i = 0;
        while (exec_i < vector::length(&execution_ratios)) {
            let ratio = *vector::borrow(&execution_ratios, exec_i);
            let executed = original * ratio / 100;

            let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
                original,
                executed,
                status,
            );

            // Verify taker ratio is always correct
            let expected_taker = (ratio as u64) * 10_000_000; // Convert to billionths
            assert_eq!(taker_ratio, expected_taker);

            // Verify maker ratio logic
            let has_maker_part =
                executed < original && (status == live() || status == partially_filled());
            if (has_maker_part) {
                assert_eq!(maker_ratio, SCALING - taker_ratio);
                assert_eq!(taker_ratio + maker_ratio, SCALING);
            } else {
                assert_eq!(maker_ratio, 0);
            };

            exec_i = exec_i + 1;
        };

        status_i = status_i + 1;
    };
}

// ===== Additional Edge Cases =====

#[test]
/// Test with invalid order status values - should treat as non-maker status
fun invalid_order_status() {
    let original = QUANTITY_MEDIUM;
    let executed = original / 2; // 50% executed

    // Test with invalid status values that don't match any known constants
    let invalid_statuses = vector[99, 255, 10, 50];

    let mut i = 0;
    while (i < vector::length(&invalid_statuses)) {
        let invalid_status = *vector::borrow(&invalid_statuses, i);
        let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
            original,
            executed,
            invalid_status,
        );

        // Invalid status should behave like non-maker status
        assert_eq!(taker_ratio, 500_000_000); // 50% taker
        assert_eq!(maker_ratio, 0); // 0% maker (unknown status = no maker part)

        i = i + 1;
    };
}

#[test]
/// Test with minimal quantities (original_quantity = 1)
fun minimal_quantities() {
    // Test smallest possible order with no execution
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        1, // original_quantity (minimal)
        0, // executed_quantity
        live(), // order_status
    );
    assert_eq!(taker_ratio, 0); // 0% taker
    assert_eq!(maker_ratio, 1_000_000_000); // 100% maker

    // Test smallest possible order with full execution
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        1, // original_quantity (minimal)
        1, // executed_quantity (fully executed)
        live(), // order_status
    );
    assert_eq!(taker_ratio, 1_000_000_000); // 100% taker
    assert_eq!(maker_ratio, 0); // 0% maker (fully executed)

    // Test minimal order with different statuses
    let statuses = vector[partially_filled(), filled(), canceled(), expired()];

    let mut i = 0;
    while (i < vector::length(&statuses)) {
        let status = *vector::borrow(&statuses, i);
        let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
            1, // original_quantity
            1, // executed_quantity (fully executed)
            status, // order_status
        );
        assert_eq!(taker_ratio, 1_000_000_000); // 100% taker
        assert_eq!(maker_ratio, 0); // 0% maker (fully executed = no maker part)

        i = i + 1;
    };
}

#[test]
/// Test single unit execution on large orders
fun single_unit_execution() {
    let large_original = 1_000_000_000_000; // 1 trillion

    // Test minimal execution on large order
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        large_original, // original_quantity
        1, // executed_quantity (single unit)
        live(), // order_status
    );
    // Expected: taker_ratio = math::div(1, 1_000_000_000_000)
    // This is (1 * 1_000_000_000) / 1_000_000_000_000 = 0.001, which rounds down to 0
    assert_eq!(taker_ratio, 0); // Rounds down to 0 due to integer division
    assert_eq!(maker_ratio, 1_000_000_000); // 100% maker when taker rounds to 0
    assert_eq!(taker_ratio + maker_ratio, 1_000_000_000); // Should sum to 100%

    // Test single unit execution with different statuses
    let maker_statuses = vector[live(), partially_filled()];
    let non_maker_statuses = vector[filled(), canceled(), expired()];

    // Test maker statuses
    let mut i = 0;
    while (i < vector::length(&maker_statuses)) {
        let status = *vector::borrow(&maker_statuses, i);
        let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
            large_original,
            1,
            status,
        );
        assert_eq!(taker_ratio, 0); // Rounds down to 0 due to integer division
        assert_eq!(maker_ratio, 1_000_000_000); // 100% maker when taker rounds to 0
        assert_eq!(taker_ratio + maker_ratio, 1_000_000_000);

        i = i + 1;
    };

    // Test non-maker statuses
    let mut i = 0;
    while (i < vector::length(&non_maker_statuses)) {
        let status = *vector::borrow(&non_maker_statuses, i);
        let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
            large_original,
            1,
            status,
        );
        assert_eq!(taker_ratio, 0); // Rounds down to 0 due to integer division
        assert_eq!(maker_ratio, 0); // No maker part for these statuses

        i = i + 1;
    };
}

#[test]
/// Test exact math boundary values
fun exact_math_boundaries() {
    // Test values that produce specific boundary results

    // Test case that produces exactly 999_999_999 taker ratio
    let original = 1_000_000_000;
    let executed = 999_999_999;
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        original,
        executed,
        live(),
    );
    assert_eq!(taker_ratio, 999_999_999); // Exactly this value
    assert_eq!(maker_ratio, 1); // Exactly 1
    assert_eq!(taker_ratio + maker_ratio, 1_000_000_000);

    // Test case that produces exactly 500_000_000 taker ratio (50%)
    let original = 2_000_000_000; // 2 billion
    let executed = 1_000_000_000; // 1 billion
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        original,
        executed,
        partially_filled(),
    );
    assert_eq!(taker_ratio, 500_000_000); // Exactly 50%
    assert_eq!(maker_ratio, 500_000_000); // Exactly 50%

    // Test case that produces exactly 333_333_333 taker ratio (1/3)
    let original = 3_000_000_000; // 3 billion
    let executed = 1_000_000_000; // 1 billion
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        original,
        executed,
        live(),
    );
    assert_eq!(taker_ratio, 333_333_333); // Exactly 1/3 (rounded down)
    assert_eq!(maker_ratio, 666_666_667); // Exactly 2/3 (rounded up)
    assert_eq!(taker_ratio + maker_ratio, 1_000_000_000);

    // Test case that produces exactly 1 taker ratio (minimal non-zero)
    let original = 1_000_000_000;
    let executed = 1;
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        original,
        executed,
        live(),
    );
    assert_eq!(taker_ratio, 1); // Exactly 1 (minimal)
    assert_eq!(maker_ratio, 999_999_999); // Almost maximum
    assert_eq!(taker_ratio + maker_ratio, 1_000_000_000);
}

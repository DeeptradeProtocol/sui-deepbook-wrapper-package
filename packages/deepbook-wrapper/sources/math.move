// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module deepbook_wrapper::math;

/// scaling setting for float
const FLOAT_SCALING_U128: u128 = 1_000_000_000;

/// Multiply two floating numbers.
/// This function will round down the result.
public(package) fun mul(x: u64, y: u64): u64 {
    let (_, result) = mul_internal(x, y);
    result
}

/// Divide two floating numbers.
/// This function will round down the result.
public(package) fun div(x: u64, y: u64): u64 {
    let (_, result) = div_internal(x, y);
    result
}

fun mul_internal(x: u64, y: u64): (u64, u64) {
    let x = (x as u128);
    let y = (y as u128);
    let round = if ((x * y) % FLOAT_SCALING_U128 == 0) 0 else 1;

    (round, ((x * y) / FLOAT_SCALING_U128 as u64))
}

fun div_internal(x: u64, y: u64): (u64, u64) {
    let x = (x as u128);
    let y = (y as u128);
    let round = if ((x * FLOAT_SCALING_U128 % y) == 0) 0 else 1;

    (round, ((x * FLOAT_SCALING_U128) / y as u64))
}

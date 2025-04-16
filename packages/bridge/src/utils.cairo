use core::num::traits::Pow;
use core::sha256::compute_sha256_u32_array;
use starknet::ContractAddress;

const SHOULD_FIT_IN_U32: felt252 = 'SHOULD_FIT_IN_U32';
/// Public Functions.

/// Calculates the SHA-256 hash of the `deposit_btc` payload for the Bridge.
///
/// The payload includes the `DEPOSIT_BTC_ACTION` constant, the to chain, recipient, amount, tx_id,
/// and vout.
pub fn calculate_sha256_for_deposit_btc_payload(
    to_chain: u128, recipient: ContractAddress, amount: u128, tx_id: u256, vout: u32,
) -> u256 {
    const DEPOSIT_BTC_ACTION: u32 = 0xf2e73f7c;

    let mut payload: Array<u32> = array![];
    payload.append(DEPOSIT_BTC_ACTION);
    append_u128_as_u256(ref payload, to_chain);
    let recipient: felt252 = recipient.into();
    append_u256(ref payload, recipient.into());
    append_u128_as_u256(ref payload, amount);
    append_u256(ref payload, tx_id);
    append_u128_as_u256(ref payload, vout.into());

    compute_sha256(arr: payload)
}


fn append_u128_as_u256(ref arr: Array<u32>, value: u128) {
    const two_pow_32: u128 = 2_u128.pow(32);
    const two_pow_64: u128 = 2_u128.pow(64);
    const two_pow_96: u128 = 2_u128.pow(96);

    // Each u32 chunk is extracted by masking with (mod) and subtracting higher powers.
    let v0 = value % two_pow_32;
    let v1 = (value / two_pow_32) % two_pow_32;
    let v2 = (value / two_pow_64) % two_pow_32;
    let v3 = (value / two_pow_96) % two_pow_32;

    // high
    arr.append(0);
    arr.append(0);
    arr.append(0);
    arr.append(0);
    // low
    arr.append(v3.try_into().expect(SHOULD_FIT_IN_U32));
    arr.append(v2.try_into().expect(SHOULD_FIT_IN_U32));
    arr.append(v1.try_into().expect(SHOULD_FIT_IN_U32));
    arr.append(v0.try_into().expect(SHOULD_FIT_IN_U32));
}

fn append_u256(ref arr: Array<u32>, value: u256) {
    const two_pow_32: u256 = 2_u256.pow(32);
    const two_pow_64: u256 = 2_u256.pow(64);
    const two_pow_96: u256 = 2_u256.pow(96);
    const two_pow_128: u256 = 2_u256.pow(128);
    const two_pow_160: u256 = 2_u256.pow(160);
    const two_pow_192: u256 = 2_u256.pow(192);
    const two_pow_224: u256 = 2_u256.pow(224);

    // Each u32 chunk is extracted by masking with (mod) and subtracting higher powers.
    let v0 = value % two_pow_32;
    let v1 = (value / two_pow_32) % two_pow_32;
    let v2 = (value / two_pow_64) % two_pow_32;
    let v3 = (value / two_pow_96) % two_pow_32;
    let v4 = (value / two_pow_128) % two_pow_32;
    let v5 = (value / two_pow_160) % two_pow_32;
    let v6 = (value / two_pow_192) % two_pow_32;
    let v7 = (value / two_pow_224) % two_pow_32;

    // high
    arr.append(v7.try_into().expect(SHOULD_FIT_IN_U32));
    arr.append(v6.try_into().expect(SHOULD_FIT_IN_U32));
    arr.append(v5.try_into().expect(SHOULD_FIT_IN_U32));
    arr.append(v4.try_into().expect(SHOULD_FIT_IN_U32));
    // low
    arr.append(v3.try_into().expect(SHOULD_FIT_IN_U32));
    arr.append(v2.try_into().expect(SHOULD_FIT_IN_U32));
    arr.append(v1.try_into().expect(SHOULD_FIT_IN_U32));
    arr.append(v0.try_into().expect(SHOULD_FIT_IN_U32));
}

fn compute_sha256(arr: Array<u32>) -> u256 {
    let sha256 = compute_sha256_u32_array(input: arr, last_input_word: 0, last_input_num_bytes: 0);

    let mut value: u256 = 0;
    for word in sha256.span() {
        value *= 0x100000000;
        value = value + (*word).into();
    }
    value
}

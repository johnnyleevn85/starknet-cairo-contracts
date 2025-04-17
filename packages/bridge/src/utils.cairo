use core::keccak::compute_keccak_byte_array;
use starknet::ContractAddress;
use starkware_utils::math::utils::u256_reverse_endian;

const U32_IN_BYTES: usize = 4;
const U128_IN_BYTES: usize = 16;

/// Public Functions.

/// Calculates the `deposit_btc` payload for the Bridge.
/// The payload includes the `DEPOSIT_BTC_ACTION` constant, the to chain, recipient, amount, tx_id,
/// and vout.
/// The payload is the same as the one used in the `build_deposit_payload`
/// function, but with the selector at the beginning.
pub fn build_deposit_payload_with_selector(deposit_payload: @ByteArray) -> ByteArray {
    const DEPOSIT_BTC_ACTION: felt252 = 0xf2e73f7c;

    let mut payload: ByteArray = Default::default();
    payload.append_word(word: DEPOSIT_BTC_ACTION, len: U32_IN_BYTES);
    payload.append(other: deposit_payload);
    payload
}

/// Calculates the `deposit_btc` payload for the Bridge.
/// The payload includes the to chain, recipient, amount, tx_id,
/// and vout.
pub fn build_deposit_payload(
    to_chain: u128, recipient: ContractAddress, amount: u128, tx_id: u256, vout: u32,
) -> ByteArray {
    let mut payload = Default::default();
    append_u128_as_u256(ref payload, to_chain);
    let recipient: felt252 = recipient.into();
    append_u256(ref payload, recipient.into());
    append_u128_as_u256(ref payload, amount);
    append_u256(ref payload, tx_id);
    append_u128_as_u256(ref payload, vout.into());
    payload
}


fn append_u128_as_u256(ref arr: ByteArray, value: u128) {
    // high
    arr.append_word(word: 0, len: U128_IN_BYTES);
    // low
    arr.append_word(word: value.into(), len: U128_IN_BYTES);
}

fn append_u256(ref arr: ByteArray, value: u256) {
    // high
    arr.append_word(word: value.high.into(), len: U128_IN_BYTES);
    // low
    arr.append_word(word: value.low.into(), len: U128_IN_BYTES);
}

pub fn compute_keccak(arr: @ByteArray) -> u256 {
    u256_reverse_endian(compute_keccak_byte_array(:arr))
}

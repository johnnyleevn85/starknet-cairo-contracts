use core::keccak::compute_keccak_byte_array;
use lbtc_bridge::errors::INVALID_DEPOSIT_PAYLOAD_LENGTH;
use starknet::ContractAddress;
use starkware_utils::math::utils::u256_reverse_endian;

const U32_IN_BYTES: usize = 4;
const U128_IN_BYTES: usize = 16;

const DEPOSIT_PAYLOAD_LENGTH: usize = 160;

/// Public Functions.

/// Adds the selector prefix to the `deposit_payload`.
pub fn build_deposit_payload_with_selector(deposit_payload: @ByteArray) -> ByteArray {
    // bytes4(keccak256("payload(bytes32,bytes32,uint64,bytes32,uint32)"))
    const DEPOSIT_BTC_ACTION: felt252 = 0xf2e73f7c;

    let mut payload: ByteArray = Default::default();
    payload.append_word(word: DEPOSIT_BTC_ACTION, len: U32_IN_BYTES);
    payload.append(other: deposit_payload);
    assert(payload.len() == DEPOSIT_PAYLOAD_LENGTH + U32_IN_BYTES, INVALID_DEPOSIT_PAYLOAD_LENGTH);
    payload
}

/// Calculates the `deposit_btc` payload for the Bridge.
/// The payload includes the to chain, recipient, amount, tx_id,
/// and vout.
pub fn build_deposit_payload(
    to_chain: u256, recipient: ContractAddress, amount: u128, tx_id: u256, vout: u32,
) -> ByteArray {
    let mut payload = Default::default();
    append_u256(ref payload, to_chain);
    let recipient: felt252 = recipient.into();
    append_u256(ref payload, recipient.into());
    append_u128_as_u256(ref payload, amount);
    append_u256(ref payload, tx_id);
    append_u128_as_u256(ref payload, vout.into());
    assert(payload.len() == DEPOSIT_PAYLOAD_LENGTH, INVALID_DEPOSIT_PAYLOAD_LENGTH);
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

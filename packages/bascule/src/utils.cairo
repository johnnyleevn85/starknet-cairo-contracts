use core::keccak::compute_keccak_byte_array;
use lbtc_bascule::errors::INVALID_DEPOSIT_PAYLOAD_LENGTH;
use starknet::ContractAddress;
use starkware_utils::math::utils::u256_reverse_endian;

const U128_IN_BYTES: usize = 16;

const DEPOSIT_PAYLOAD_LENGTH: usize = 160;

/// Public Functions.

/// Calculates the `deposit_btc` payload for the Asset Router.
/// The payload includes the to chain, recipient, amount, tx_id,
/// and vout.
pub fn build_deposit_payload(
    to_chain: u256, recipient: ContractAddress, amount: u256, tx_id: u256, vout: u32,
) -> ByteArray {
    let mut payload = Default::default();
    append_u256(ref payload, to_chain);
    let recipient: felt252 = recipient.into();
    append_u256(ref payload, recipient.into());
    append_u256(ref payload, amount);
    append_u256(ref payload, tx_id);
    append_u128_as_u256(ref payload, vout.into());
    assert(payload.len() == DEPOSIT_PAYLOAD_LENGTH, INVALID_DEPOSIT_PAYLOAD_LENGTH);
    payload
}

/// Returns the deposit id.
pub fn calculate_deposit_id(
    to_chain: u256, recipient: ContractAddress, withdrawal_amount: u256, tx_id: u256, vout: u32,
) -> u256 {
    let payload = build_deposit_payload(
        :to_chain, :recipient, amount: withdrawal_amount, :tx_id, :vout,
    );
    compute_keccak(arr: @payload)
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

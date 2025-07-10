use core::dict::Felt252Dict;
use core::num::traits::Pow;
use core::sha256::compute_sha256_u32_array;
use core::traits::DivRem;
use lbtc_consortium::interface::PublicKey;
use starknet::eth_address::EthAddress;
use starkware_utils::math::utils::u256_from_u32_array;

const SHOULD_FIT_IN_U32: felt252 = 'SHOULD_FIT_IN_U32';
/// Public Functions.

/// Calculates the SHA-256 hash of the `set_next_validator_set` payload for the consortium.
///
/// The payload includes the `NEW_VALSET` constant, the epoch, the list of public keys, their
/// weights, the threshold weight, and the height.
pub fn calculate_sha256_for_set_next_validator_set_payload(
    epoch: u64,
    public_keys: Span<PublicKey>,
    weights: Span<u128>,
    threshold_weight: u128,
    height: u128,
) -> u256 {
    // Constants.
    // bytes4(keccak256("payload(uint256,bytes[],uint256[],uint256,uint256)")).
    const NEW_VALSET: u32 = 0x4aab1d6f;
    const N_BYTES_256: u128 = 32;
    const N_SET_NEXT_VALIDATOR_SET_PARAMS: u128 = 5;
    const N_PUB_KEYS_SLOTS: u128 = 5;

    let mut payload: Array<u32> = array![];
    payload.append(NEW_VALSET);

    // Epoch.
    append_u128_as_u256(ref arr: payload, value: epoch.into());

    // Public keys offset.
    let public_keys_offset = N_SET_NEXT_VALIDATOR_SET_PARAMS * N_BYTES_256;
    append_u128_as_u256(ref arr: payload, value: public_keys_offset);

    // Weights offset: 1 for public_keys' len.
    let public_keys_len = public_keys.len();
    // One for the public keys len.
    let weights_offset = (N_SET_NEXT_VALIDATOR_SET_PARAMS
        + 1
        + N_PUB_KEYS_SLOTS * public_keys_len.into())
        * N_BYTES_256;
    append_u128_as_u256(ref arr: payload, value: weights_offset);

    // Threshold weight.
    append_u128_as_u256(ref arr: payload, value: threshold_weight);

    // Height.
    append_u128_as_u256(ref arr: payload, value: height);

    // Public keys length.
    append_pub_keys(ref arr: payload, public_keys: public_keys);

    // Weights length.
    append_weights(ref arr: payload, :weights);

    u256_from_u32_array(
        compute_sha256_u32_array(input: payload, last_input_word: 0, last_input_num_bytes: 0),
    )
}


/// Private Functions.

fn append_pub_keys(ref arr: Array<u32>, public_keys: Span<PublicKey>) {
    let public_keys_len = public_keys.len();
    let N_BYTES_256 = 32_u32;

    let base_offset = public_keys_len * N_BYTES_256;
    let N_BYTES_PK = 4_u32.into() * N_BYTES_256;

    append_u128_as_u256(ref arr, public_keys_len.into());

    // Offsets:
    for i in 0..public_keys_len {
        append_u128_as_u256(ref arr, base_offset.into() + i.into() * N_BYTES_PK.into());
    }

    for public_key in public_keys {
        let (x, y) = public_key;

        // size.
        append_u128_as_u256(ref arr, 0x41_u128);

        // Serialize an uncompressed public key (0x04 || x || y) into three 256-bit words:
        // - Each coordinate (x, y) is 32 bytes; the prefix 0x04 makes 65 bytes total.
        // - v0 contains: 0x04 prefix (1 byte) + first 31 bytes of x.
        // - v1 contains: last byte of x + first 31 bytes of y.
        // - v2 contains: last byte of y + 31 zero bytes (padding).
        let prefix = 0x04_u256;

        let (x_high_bytes, x_low_byte) = DivRem::div_rem(*x, 256);
        let (y_high_bytes, y_low_byte) = DivRem::div_rem(*y, 256);

        let v0 = prefix * 2_u256.pow(248) + x_high_bytes;
        let v1 = x_low_byte * 2_u256.pow(248) + y_high_bytes;
        let v2 = y_low_byte * 2_u256.pow(248);

        append_u256(ref arr, v0);
        append_u256(ref arr, v1);
        append_u256(ref arr, v2);
    }
}

fn append_weights(ref arr: Array<u32>, weights: Span<u128>) {
    append_u128_as_u256(ref arr, weights.len().into());
    for weight in weights {
        append_u128_as_u256(ref arr, value: (*weight).into());
    }
}

fn append_u128(ref arr: Array<u32>, value: u128) {
    const two_pow_32: u128 = 2_u128.pow(32);
    const two_pow_64: u128 = 2_u128.pow(64);
    const two_pow_96: u128 = 2_u128.pow(96);

    // Each u32 chunk is extracted by masking with (mod) and subtracting higher powers.
    let v0 = value % two_pow_32;
    let v1 = (value / two_pow_32) % two_pow_32;
    let v2 = (value / two_pow_64) % two_pow_32;
    let v3 = (value / two_pow_96) % two_pow_32;

    arr.append(v3.try_into().expect(SHOULD_FIT_IN_U32));
    arr.append(v2.try_into().expect(SHOULD_FIT_IN_U32));
    arr.append(v1.try_into().expect(SHOULD_FIT_IN_U32));
    arr.append(v0.try_into().expect(SHOULD_FIT_IN_U32));
}

fn append_u128_as_u256(ref arr: Array<u32>, value: u128) {
    // high
    arr.append(0);
    arr.append(0);
    arr.append(0);
    arr.append(0);
    // low
    append_u128(ref arr, value);
}

fn append_u256(ref arr: Array<u32>, value: u256) {
    // high
    append_u128(ref arr, value.high);
    // low
    append_u128(ref arr, value.low);
}

pub fn insert_if_unique(ref address_set: Felt252Dict<bool>, eth_address: EthAddress) -> bool {
    let address_felt252 = eth_address.into();
    // Validate no duplication.
    let is_address_exist = address_set.get(address_felt252);
    if is_address_exist {
        return false;
    }

    address_set.insert(address_felt252, true);
    true
}

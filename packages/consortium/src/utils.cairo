use alexandria_bytes::BytesTrait;
use core::dict::Felt252Dict;
use core::num::traits::Pow;
use core::sha256::compute_sha256_u32_array;
use lbtc_consortium::errors::{DUPLICATED_PUBLIC_KEY, INVALID_PUBLIC_KEY};
use starknet::SyscallResultTrait;
use starknet::eth_address::EthAddress;
use starknet::eth_signature::public_key_point_to_eth_address;
use starknet::secp256_trait::{Secp256Trait, Signature, recover_public_key};
use starknet::secp256k1::Secp256k1Point;

pub fn is_signature_by_signer(signer: EthAddress, msg_hash: u256, signature: Signature) -> bool {
    if let Option::Some(public_key_point) =
        recover_public_key::<Secp256k1Point>(:msg_hash, :signature) {
        let address = public_key_point_to_eth_address(:public_key_point);
        if (address == signer) {
            return true;
        }
    }
    false
}

// TODO(Mohammad): remove deprecated calculation.
/// Calculates the SHA-256 hash of the `set_next_validator_set` payload for the consortium.
///
/// The payload includes the `NEW_VALSET` constant, the epoch, the list of validators, their
/// weights, the threshold weight, and the height.
#[feature("deprecated-sha256")]
pub fn deprecated_calculate_hash_for_next_validators(
    epoch: u64,
    validators: @Array<EthAddress>,
    weights: @Array<u128>,
    threshold_weight: u128,
    height: u128,
) -> u256 {
    // Constants.
    // bytes4(keccak256("payload(uint256,bytes[],uint256[],uint256,uint256)")).
    const NEW_VALSET: u32 = 0x4aab1d6f;
    const N_BYTES_256: u32 = 32;
    const N_NEXT_VALIDATOR_PAYLOAD_ARGS: u32 = 5;

    let mut payload = BytesTrait::new_empty();

    payload.append_u32(NEW_VALSET);

    // Epoch.
    payload.append_u256(epoch.into());

    // Validators offset.
    let validators_offset = N_NEXT_VALIDATOR_PAYLOAD_ARGS * N_BYTES_256;
    payload.append_u256(validators_offset.into());

    // Weights offset: 1 for validators' len.
    let validators_len = validators.len();
    let weights_offset = (N_NEXT_VALIDATOR_PAYLOAD_ARGS + 1 + validators_len) * N_BYTES_256;
    payload.append_u256(weights_offset.into());

    // Threshold weight.
    payload.append_u256(threshold_weight.into());

    // Height.
    payload.append_u256(height.into());

    // Validators length.
    payload.append_u256(validators_len.into());
    for validator in validators {
        let validator_felt252: felt252 = (*validator).into();
        payload.append_u256(validator_felt252.into());
    }

    // Weights length.
    payload.append_u256(validators_len.into());
    for weight in weights {
        payload.append_u256((*weight).into());
    }

    payload.sha256()
}


const SHOULD_FIT_IN_U32: felt252 = 'SHOULD_FIT_IN_U32';
/// Public Functions.

/// Calculates the SHA-256 hash of the `set_next_validator_set` payload for the consortium.
///
/// The payload includes the `NEW_VALSET` constant, the epoch, the list of public keys, their
/// weights, the threshold weight, and the height.
pub fn calculate_sha256_for_set_next_validator_set_paylod(
    epoch: u64,
    public_keys: @Array<(u256, u256)>,
    weights: @Array<u128>,
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
    append_weights(ref arr: payload, values: weights);

    compute_sha256(arr: payload)
}


/// Private Functions.

fn append_pub_keys(ref arr: Array<u32>, public_keys: @Array<(u256, u256)>) {
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
        let x_high_bytes = *x / 2_u256.pow(8);
        let x_low_bytes = *x % 2_u256.pow(8);
        let y_high_bytes = *y / 2_u256.pow(8);
        let y_low_bytes = *y % 2_u256.pow(8);

        let v0 = prefix * 2_u256.pow(248) + x_high_bytes;
        let v1 = x_low_bytes * 2_u256.pow(248) + y_high_bytes;
        let v2 = y_low_bytes * 2_u256.pow(248);

        append_u256_u32_limbs(ref arr, v0);
        append_u256_u32_limbs(ref arr, v1);
        append_u256_u32_limbs(ref arr, v2);
    }
}

fn append_weights(ref arr: Array<u32>, values: @Array<u128>) {
    append_u128_as_u256(ref arr, values.len().into());
    for value in values {
        append_u128_as_u256(ref arr, (*value).into());
    }
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

fn append_u256_u32_limbs(ref arr: Array<u32>, value: u256) {
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

pub fn generate_eth_addresses_from_pks(public_keys: @Array<(u256, u256)>) -> Array<EthAddress> {
    let mut eth_addresses: Array<EthAddress> = array![];
    for pk in public_keys {
        let (x, y) = *pk;
        let secp_point = Secp256Trait::<Secp256k1Point>::secp256_ec_new_syscall(x, y)
            .unwrap_syscall()
            .expect(INVALID_PUBLIC_KEY);
        let eth_address = public_key_point_to_eth_address(secp_point);
        eth_addresses.append(eth_address);
    }

    eth_addresses
}

pub fn ensure_uniqueness(ref address_dict: Felt252Dict<bool>, eth_address: EthAddress) {
    let address_felt252 = eth_address.into();
    let is_address_exist = address_dict.get(address_felt252);
    // Validate no duplication.
    assert(!is_address_exist, DUPLICATED_PUBLIC_KEY);
    address_dict.insert(address_felt252, true);
}

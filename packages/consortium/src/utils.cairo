use alexandria_bytes::BytesTrait;
use starknet::eth_address::EthAddress;

/// Calculates the SHA-256 hash of the `set_next_validator_set` payload for the consortium.
///
/// The payload includes the `NEW_VALSET` constant, the epoch, the list of validators, their
/// weights, the threshold weight, and the height.
#[feature("deprecated-sha256")]
pub fn calculate_hash_for_next_validators(
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

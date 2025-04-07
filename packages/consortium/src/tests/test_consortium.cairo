use lbtc_consortium::errors::{
    DUPLICATED_PUBLIC_KEY, INVALID_VALIDATOR_SET_SIZE, INVALID_ZERO_WEIGHT_THRESHOLD,
    VALIDATORS_ALREADY_INITIALIZED, VALIDATORS_WEIGHTS_LEN_MISMATCH,
};
use lbtc_consortium::interface::{
    IConsortiumDispatcher, IConsortiumDispatcherTrait, IConsortiumSafeDispatcher,
    IConsortiumSafeDispatcherTrait,
};
use lbtc_consortium::tests::test_utils::init_contract_with_roles;
use starknet::eth_address::EthAddress;
use starknet::secp256_trait::Signature;
use starkware_utils_testing::constants::APP_GOVERNOR;
use starkware_utils_testing::test_utils::{
    assert_panic_with_error, assert_panic_with_felt_error, cheat_caller_address_once,
};

#[test]
fn test_successful_initial_validator_set() {
    // Setup:
    let contract_address = init_contract_with_roles();
    let dispatcher = IConsortiumDispatcher { contract_address };

    // Params:
    let validator_1: EthAddress = 0x123_u256.try_into().unwrap();
    let validator_2: EthAddress = 0x456_u256.try_into().unwrap();
    let validator_3: EthAddress = 0x789_u256.try_into().unwrap();
    let validators = array![validator_1, validator_2, validator_3];
    let weights = array![10, 20, 30];
    let threshold_weight = 50;

    // Test:
    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher.set_initial_validator_set(:validators, :weights, :threshold_weight);

    // Check:
    assert_eq!(dispatcher.get_current_epoch(), 1);
    assert_eq!(
        dispatcher.get_validator_set(epoch: 1),
        (array![validator_1, validator_2, validator_3], array![10, 20, 30], threshold_weight),
    );
}

#[test]
#[feature("safe_dispatcher")]
fn test_illegal_initial_validator_set() {
    // Setup:
    let contract_address = init_contract_with_roles();
    let dispatcher = IConsortiumSafeDispatcher { contract_address };

    // Params:
    let validator_1: EthAddress = 0x123_u256.try_into().unwrap();
    let validator_2: EthAddress = 0x456_u256.try_into().unwrap();
    let validator_3: EthAddress = 0x789_u256.try_into().unwrap();
    let validators = array![validator_1, validator_2, validator_3];
    let weights = array![10, 20, 30];
    let threshold_weight = 50;

    // Test:
    let result = dispatcher
        .set_initial_validator_set(validators: array![], weights: array![], :threshold_weight);
    assert_panic_with_error(:result, expected_error: "ONLY_APP_GOVERNOR");

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(validators: array![], weights: array![], :threshold_weight);
    assert_panic_with_felt_error(:result, expected_error: INVALID_VALIDATOR_SET_SIZE);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(validators: array![], weights: array![1], :threshold_weight);
    assert_panic_with_felt_error(:result, expected_error: VALIDATORS_WEIGHTS_LEN_MISMATCH);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(validators: array![], weights: array![], threshold_weight: 0);
    assert_panic_with_felt_error(:result, expected_error: INVALID_ZERO_WEIGHT_THRESHOLD);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(
            validators: array![validator_1, validator_1], weights: array![1, 2], :threshold_weight,
        );
    assert_panic_with_felt_error(:result, expected_error: DUPLICATED_PUBLIC_KEY);

    // Successful initialization.
    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher.set_initial_validator_set(:validators, :weights, :threshold_weight).unwrap();

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(validators: array![], weights: array![], :threshold_weight);
    assert_panic_with_felt_error(:result, expected_error: VALIDATORS_ALREADY_INITIALIZED);
}


#[test]
fn test_successful_check_proof() {
    // Setup:
    let contract_address = init_contract_with_roles();
    let dispatcher = IConsortiumDispatcher { contract_address };

    // Params:
    let validator: EthAddress = 0x767410c1bb448978bd42b984d7de5970bcaf5c43_u256.try_into().unwrap();
    let msg_hash = 0xe888fbb4cf9ae6254f19ba12e6d9af54788f195a6f509ca3e934f78d7a71dd85;
    let r = 0x4c8e4fbc1fbb1dece52185e532812c4f7a5f81cf3ee10044320a0d03b62d3e9a;
    let s = 0x4ac5e5c0c0e8a4871583cc131f35fb49c2b7f60e6a8b84965830658f08f7410c;
    let y_parity = true;
    let signature = Signature { r, s, y_parity };

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher
        .set_initial_validator_set(
            validators: array![validator], weights: array![10], threshold_weight: 5,
        );

    // Test:
    dispatcher.check_proof(payload_hash: msg_hash, proof: array![signature]);
    // Test passes if `check_proof` did not panic.
}


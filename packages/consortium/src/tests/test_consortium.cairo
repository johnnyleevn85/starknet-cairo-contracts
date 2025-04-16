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
    let pk_1 = (
        0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d9_u256,
        0x6a50131029f32effbe5d8ba0da8c75760ff5add90c77efcd48eeebbf56094bd8_u256,
    );
    let address_1: EthAddress = 0x00000000000000000000000068f830fb84b7d10f130561d7decf22d00d0edb1a
        .try_into()
        .unwrap();

    let pk_2 = (
        0x5db8a04eda553ca964383c6abe44de2ac85df22fb61062dbdc33ccef06d81ea0_u256,
        0x2926c0d2ba062d0b02bd23631242169239e0b4509990c04304717d510727a300_u256,
    );
    let address_2: EthAddress = 0x0000000000000000000000004076832c496fbc4f2576f497ff9b697d114174d9
        .try_into()
        .unwrap();

    let pk_3 = (
        0xd9bee4a028efa3eaca7134e953bad6378aa4085e7e7887de7ef249e735ef156d,
        0x83f08fa5fbb65fed7b736b61247bbd522f1d03b5fbdda7d4b83519ea11c67319,
    );
    let address_3: EthAddress = 0x0000000000000000000000009d224c7b54eaa798ea9f0c4dbc93d47ba73a46ab
        .try_into()
        .unwrap();

    let public_keys = array![pk_1, pk_2, pk_3];
    let weights = array![20, 20, 20];
    let threshold_weight = 50;

    // Test:
    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher.set_initial_validator_set(validators: public_keys, :weights, :threshold_weight);

    // Check:
    assert_eq!(dispatcher.get_current_epoch(), 1);
    assert_eq!(
        dispatcher.get_validator_set(epoch: 1),
        (array![address_1, address_2, address_3], array![20, 20, 20], threshold_weight),
    );
}

#[test]
#[feature("safe_dispatcher")]
fn test_illegal_initial_validator_set() {
    // Setup:
    let contract_address = init_contract_with_roles();
    let dispatcher = IConsortiumSafeDispatcher { contract_address };

    // Params:
    let pk_1 = (
        0xea76f134e8171960d05fc3dca6da40665a060a75f43df5ff33fa799889cf3ba5_u256,
        0x8d1d43611d9dc6f59a2abdb1d2ddeb5be22879f3e01b88d7a91993939f1f5025_u256,
    );
    let pk_2 = (
        0xe6659f2f445f9cc7982bd27b3b9231f185092cdeedc60921388278ce2d45ca0d_u256,
        0x54f5365f3d0297e6fcc24842b48417b33dfe84a0c40488c8811648972d49b1aa_u256,
    );
    let pk_3 = (
        0x37ffff9fc040fbd0ce7d1cc580e42c6a67bb3ec4321ca7634a06ab781105cc25,
        0x6b6217249c4e75ee09f3503ebbbadf8b00558e552480abddbfe626c1ed60191f_u256,
    );
    let pks = array![pk_1, pk_2, pk_3];
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
            validators: array![pk_1, pk_1], weights: array![1, 2], :threshold_weight,
        );
    assert_panic_with_felt_error(:result, expected_error: DUPLICATED_PUBLIC_KEY);

    // Successful initialization.
    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher.set_initial_validator_set(validators: pks, :weights, :threshold_weight).unwrap();

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
    let public_key = (
        0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d9_u256,
        0x6a50131029f32effbe5d8ba0da8c75760ff5add90c77efcd48eeebbf56094bd8_u256,
    );
    let msg_hash = 0x8917d1b016548996625c37d4ac902ccc5951f248ab8466a640a98fa7864de548;
    let r = 0xfb67498ff38109a13c81d9d8447d1f09c55a2a71f2d437d8944f422af5fff77b;
    let s = 0x1e0a7a24ac2e845c1ea559e8697472fe496d16856d12a7b27d5b64d0a7b53989;
    let signature = (r, s);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher
        .set_initial_validator_set(
            validators: array![public_key], weights: array![10], threshold_weight: 5,
        );

    // Test:
    dispatcher.check_proof(:msg_hash, proof: array![signature].span());
    // Test passes if `check_proof` did not panic.
}


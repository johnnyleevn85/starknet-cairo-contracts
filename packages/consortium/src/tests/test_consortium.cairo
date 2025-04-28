use lbtc_consortium::errors::{
    DUPLICATED_SIGNATURE, DUPLICATED_VALIDATOR, INVALID_EPOCH, INVALID_VALIDATOR_SET_SIZE,
    INVALID_ZERO_WEIGHT_THRESHOLD, PUB_KEYS_WEIGHTS_LEN_MISMATCH, VALIDATORS_WERE_NOT_INITIALIZED,
};
use lbtc_consortium::interface::{
    IConsortiumDispatcher, IConsortiumDispatcherTrait, IConsortiumSafeDispatcher,
    IConsortiumSafeDispatcherTrait, Signature,
};
use lbtc_testing::utils::consortium::init_contract_with_roles;
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

    let public_keys = array![pk_1, pk_2, pk_3].span();
    let weights = array![20, 20, 20].span();
    let threshold_weight = 50;

    // Test:
    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher.set_initial_validator_set(:public_keys, :weights, :threshold_weight);

    // Check:
    assert_eq!(dispatcher.get_current_epoch(), 1);
    assert_eq!(
        dispatcher.get_validator_set(epoch: 1),
        (
            array![address_1, address_2, address_3].span(),
            array![20, 20, 20].span(),
            threshold_weight,
        ),
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
    let pks = array![pk_1, pk_2, pk_3].span();
    let weights = array![10, 20, 30].span();
    let threshold_weight = 50;

    // Test:
    let result = dispatcher
        .set_initial_validator_set(
            public_keys: array![].span(), weights: array![].span(), :threshold_weight,
        );
    assert_panic_with_error(:result, expected_error: "ONLY_APP_GOVERNOR");

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(
            public_keys: array![].span(), weights: array![].span(), :threshold_weight,
        );
    assert_panic_with_felt_error(:result, expected_error: INVALID_VALIDATOR_SET_SIZE);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(
            public_keys: array![].span(), weights: array![1].span(), :threshold_weight,
        );
    assert_panic_with_felt_error(:result, expected_error: PUB_KEYS_WEIGHTS_LEN_MISMATCH);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(
            public_keys: array![].span(), weights: array![].span(), threshold_weight: 0,
        );
    assert_panic_with_felt_error(:result, expected_error: INVALID_ZERO_WEIGHT_THRESHOLD);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(
            public_keys: array![pk_1, pk_1].span(), weights: array![1, 2].span(), :threshold_weight,
        );
    assert_panic_with_felt_error(:result, expected_error: DUPLICATED_VALIDATOR);

    // Successful initialization.
    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher.set_initial_validator_set(public_keys: pks, :weights, :threshold_weight).unwrap();

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(
            public_keys: array![].span(), weights: array![].span(), :threshold_weight,
        );
    assert_panic_with_felt_error(:result, expected_error: INVALID_EPOCH);
}

#[test]
#[feature("safe_dispatcher")]
fn test_illegal_set_next_validator_set() {
    // Setup:
    let contract_address = init_contract_with_roles();
    let dispatcher = IConsortiumSafeDispatcher { contract_address };

    // Params:
    let public_key_1 = (
        0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d9_u256,
        0x6a50131029f32effbe5d8ba0da8c75760ff5add90c77efcd48eeebbf56094bd8_u256,
    );
    let public_key_2 = (
        0xd9bee4a028efa3eaca7134e953bad6378aa4085e7e7887de7ef249e735ef156d_u256,
        0x83f08fa5fbb65fed7b736b61247bbd522f1d03b5fbdda7d4b83519ea11c67319_u256,
    );
    let public_keys = array![public_key_1, public_key_2].span();
    let weights = array![20, 30].span();
    let height = 1234321;
    let threshold_weight = 25;
    let proof: Span<Signature> = array![].span();

    // Test:
    for epoch in array![0, 2, 33] {
        let result = dispatcher
            .set_next_validator_set(
                :epoch,
                public_keys: array![].span(),
                weights: array![].span(),
                :threshold_weight,
                :height,
                proof: proof.clone(),
            );
        assert_panic_with_felt_error(:result, expected_error: INVALID_EPOCH);
    }

    let result = dispatcher
        .set_next_validator_set(
            epoch: 1,
            public_keys: array![public_key_1].span(),
            weights: array![20].span(),
            :threshold_weight,
            :height,
            proof: proof.clone(),
        );
    assert_panic_with_felt_error(:result, expected_error: VALIDATORS_WERE_NOT_INITIALIZED);

    // Successful set initial validators.
    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher.set_initial_validator_set(:public_keys, :weights, :threshold_weight).unwrap();

    let result = dispatcher
        .set_next_validator_set(
            epoch: 2,
            public_keys: array![].span(),
            weights: array![].span(),
            :threshold_weight,
            :height,
            proof: proof.clone(),
        );
    assert_panic_with_felt_error(:result, expected_error: INVALID_VALIDATOR_SET_SIZE);

    let result = dispatcher
        .set_next_validator_set(
            epoch: 2,
            public_keys: array![].span(),
            weights: array![1].span(),
            :threshold_weight,
            :height,
            proof: proof.clone(),
        );
    assert_panic_with_felt_error(:result, expected_error: PUB_KEYS_WEIGHTS_LEN_MISMATCH);

    let result = dispatcher
        .set_next_validator_set(
            epoch: 2,
            public_keys: array![public_key_1].span(),
            weights: array![30].span(),
            threshold_weight: 0,
            :height,
            proof: proof.clone(),
        );
    assert_panic_with_felt_error(:result, expected_error: INVALID_ZERO_WEIGHT_THRESHOLD);
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
            public_keys: array![public_key].span(), weights: array![10].span(), threshold_weight: 5,
        );

    // Test:
    dispatcher.check_proof(:msg_hash, proof: array![signature].span());
    // Test passes if `check_proof` did not panic.
}


#[test]
#[should_panic(expected_error: 'DUPLICATED_SIGNATURE')]
fn test_successful_check_proof_duplicate_signature() {
    // Setup:
    let contract_address = init_contract_with_roles();
    let dispatcher = IConsortiumDispatcher { contract_address };

    // Params:
    let public_key1 = (
        0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d9_u256,
        0x6a50131029f32effbe5d8ba0da8c75760ff5add90c77efcd48eeebbf56094bd8_u256,
    );
    let public_key2 = (
        0xd9bee4a028efa3eaca7134e953bad6378aa4085e7e7887de7ef249e735ef156d_u256,
        0x83f08fa5fbb65fed7b736b61247bbd522f1d03b5fbdda7d4b83519ea11c67319_u256,
    );
    let msg_hash = 0x8917d1b016548996625c37d4ac902ccc5951f248ab8466a640a98fa7864de548;
    let r = 0xfb67498ff38109a13c81d9d8447d1f09c55a2a71f2d437d8944f422af5fff77b;
    let s = 0x1e0a7a24ac2e845c1ea559e8697472fe496d16856d12a7b27d5b64d0a7b53989;
    let signature = (r, s);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher
        .set_initial_validator_set(
            public_keys: array![public_key1, public_key2].span(),
            weights: array![4, 4].span(),
            threshold_weight: 5,
        );

    // Test:
    dispatcher.check_proof(:msg_hash, proof: array![signature, signature].span());
    // Test passes if `check_proof` did not panic.
}


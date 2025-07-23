use lbtc_consortium::errors::{
    DUPLICATED_VALIDATOR, INVALID_EPOCH, INVALID_VALIDATOR_SET_SIZE, INVALID_ZERO_WEIGHT_THRESHOLD,
    NOT_ENOUGH_SIGNATURES, PUB_KEYS_WEIGHTS_LEN_MISMATCH, TOTAL_WEIGHT_UNDER_THRESHOLD,
    VALIDATORS_SET_ALREADY_SET, VALIDATORS_WERE_NOT_INITIALIZED,
};
use lbtc_consortium::interface::{
    IConsortiumDispatcher, IConsortiumDispatcherTrait, IConsortiumSafeDispatcher,
    IConsortiumSafeDispatcherTrait, Signature,
};
use lbtc_consortium::utils::calculate_sha256_for_set_next_validator_set_payload;
use lbtc_testing::utils::consortium::{generate_public_key, init_contract_with_roles};
use snforge_std::signature::secp256k1_curve::{Secp256k1CurveKeyPairImpl, Secp256k1CurveSignerImpl};
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
    let new_epoch = 3;
    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher
        .set_initial_validator_set(epoch: new_epoch, :public_keys, :weights, :threshold_weight);

    // Check:
    assert_eq!(dispatcher.get_current_epoch(), new_epoch);
    assert_eq!(
        dispatcher.get_validator_set(epoch: new_epoch),
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
            epoch: 1, public_keys: array![].span(), weights: array![].span(), :threshold_weight,
        );
    assert_panic_with_error(:result, expected_error: "ONLY_APP_GOVERNOR");

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(
            epoch: 1, public_keys: array![].span(), weights: array![].span(), :threshold_weight,
        );
    assert_panic_with_felt_error(:result, expected_error: INVALID_VALIDATOR_SET_SIZE);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(
            epoch: 1, public_keys: array![].span(), weights: array![1].span(), :threshold_weight,
        );
    assert_panic_with_felt_error(:result, expected_error: PUB_KEYS_WEIGHTS_LEN_MISMATCH);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(
            epoch: 1, public_keys: array![].span(), weights: array![].span(), threshold_weight: 0,
        );
    assert_panic_with_felt_error(:result, expected_error: INVALID_ZERO_WEIGHT_THRESHOLD);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(
            epoch: 1,
            public_keys: array![pk_1, pk_1].span(),
            weights: array![1, 2].span(),
            :threshold_weight,
        );
    assert_panic_with_felt_error(:result, expected_error: DUPLICATED_VALIDATOR);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(
            epoch: 0,
            public_keys: array![pk_1, pk_1].span(),
            weights: array![1, 2].span(),
            :threshold_weight,
        );
    assert_panic_with_felt_error(:result, expected_error: INVALID_EPOCH);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(epoch: 1, public_keys: pks, :weights, threshold_weight: 61);
    assert_panic_with_felt_error(:result, expected_error: TOTAL_WEIGHT_UNDER_THRESHOLD);

    // Successful initialization.
    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher
        .set_initial_validator_set(epoch: 1, public_keys: pks, :weights, :threshold_weight)
        .unwrap();

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    let result = dispatcher
        .set_initial_validator_set(
            epoch: 1, public_keys: array![].span(), weights: array![].span(), :threshold_weight,
        );
    assert_panic_with_felt_error(:result, expected_error: VALIDATORS_SET_ALREADY_SET);
}

#[test]
fn test_successful_next_validator_set() {
    // Setup:
    let contract_address = init_contract_with_roles();
    let dispatcher = IConsortiumDispatcher { contract_address };

    // Params:
    let epoch = 2;
    let threshold_weight = 7;
    let height = 14641;
    let pk_2 = (
        0x5db8a04eda553ca964383c6abe44de2ac85df22fb61062dbdc33ccef06d81ea0_u256,
        0x2926c0d2ba062d0b02bd23631242169239e0b4509990c04304717d510727a300_u256,
    );
    let address_2: EthAddress = 0x0000000000000000000000004076832c496fbc4f2576f497ff9b697d114174d9
        .try_into()
        .unwrap();
    let address_3: EthAddress = 0x0000000000000000000000009d224c7b54eaa798ea9f0c4dbc93d47ba73a46ab
        .try_into()
        .unwrap();
    let pk_3 = (
        0xd9bee4a028efa3eaca7134e953bad6378aa4085e7e7887de7ef249e735ef156d,
        0x83f08fa5fbb65fed7b736b61247bbd522f1d03b5fbdda7d4b83519ea11c67319,
    );
    let public_keys = array![pk_2, pk_3].span();
    let weights = array![10, 5].span();
    let secret_key = 0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d9_u256;

    // Test:
    let (public_key, key_pair) = generate_public_key(:secret_key);
    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher
        .set_initial_validator_set(
            epoch: 1,
            public_keys: array![public_key].span(),
            weights: array![1].span(),
            threshold_weight: 1,
        );

    let msg_hash = calculate_sha256_for_set_next_validator_set_payload(
        :epoch, :public_keys, :weights, :threshold_weight, :height,
    );
    let (r, s) = key_pair.sign(msg_hash).unwrap();
    dispatcher
        .set_next_validator_set(
            :epoch,
            :public_keys,
            :weights,
            :threshold_weight,
            :height,
            proof: array![(r, s)].span(),
        );

    // Check:
    assert_eq!(dispatcher.get_current_epoch(), 2);
    assert_eq!(
        dispatcher.get_validator_set(epoch: 2),
        (array![address_2, address_3].span(), array![10, 5].span(), threshold_weight),
    );
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
    dispatcher
        .set_initial_validator_set(epoch: 1, :public_keys, :weights, :threshold_weight)
        .unwrap();

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

    let result = dispatcher
        .set_next_validator_set(
            epoch: 2,
            public_keys: array![public_key_1].span(),
            weights: array![30].span(),
            threshold_weight: 31,
            :height,
            proof: proof.clone(),
        );
    assert_panic_with_felt_error(:result, expected_error: NOT_ENOUGH_SIGNATURES);
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
    let invalid_signature = (
        0xfb67498ff38109a13c81d9d8447d1f09c55a2a71f2d437d8944f422af5fff77b_u256,
        0xfb67498ff38109a13c81d9d8447d1f09c55a2a71f2d437d8944f422af5fff77b_u256,
    );
    let zero_signature = (0_u256, 0_u256);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher
        .set_initial_validator_set(
            epoch: 1,
            public_keys: array![public_key].span(),
            weights: array![10].span(),
            threshold_weight: 5,
        );

    // Tests:
    dispatcher.check_proof(:msg_hash, proof: array![signature].span());
    dispatcher.check_proof(:msg_hash, proof: array![signature, signature].span());
    dispatcher.check_proof(:msg_hash, proof: array![zero_signature, signature].span());
    dispatcher.check_proof(:msg_hash, proof: array![signature, zero_signature].span());
    dispatcher.check_proof(:msg_hash, proof: array![invalid_signature, signature].span());
    // Test passes if `check_proof`s did not panic.
}


#[test]
#[feature("safe_dispatcher")]
fn test_check_proof_invalid_scenarios() {
    // Setup:
    let contract_address = init_contract_with_roles();
    let dispatcher = IConsortiumSafeDispatcher { contract_address };

    // Params:
    let msg_hash = 0x8917d1b016548996625c37d4ac902ccc5951f248ab8466a640a98fa7864de548;

    let secret_key_1 = 0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d9_u256;
    let secret_key_2 = 0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d8_u256;
    let secret_key_3 = 0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d7_u256;
    let secret_key_4 = 0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b1234472d4621081d7_u256;

    let (public_key_1, key_pair_1) = generate_public_key(secret_key: secret_key_1);
    let (public_key_2, key_pair_2) = generate_public_key(secret_key: secret_key_2);
    let (public_key_3, key_pair_3) = generate_public_key(secret_key: secret_key_3);
    let (public_key_4, key_pair_4) = generate_public_key(secret_key: secret_key_4);

    let signature_1 = key_pair_1.sign(msg_hash).unwrap();
    let signature_2 = key_pair_2.sign(msg_hash).unwrap();
    let signature_3 = key_pair_3.sign(msg_hash).unwrap();
    let signature_4 = key_pair_4.sign(msg_hash).unwrap();
    let invalid_signature = (
        0x4567498ff38109a13c81d9d8447d1f09c55a2a71f2d437d8944f422af5fff77b_u256,
        0xfb67498ff38109a13c81d9d8447d1f09c55a2a71f2d437d8944f422af5fff77b_u256,
    );
    let zero_signature = (0_u256, 0_u256);

    let result = dispatcher.check_proof(:msg_hash, proof: array![signature_3].span());
    assert_panic_with_felt_error(:result, expected_error: VALIDATORS_WERE_NOT_INITIALIZED);

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher
        .set_initial_validator_set(
            epoch: 1,
            public_keys: array![public_key_1, public_key_2, public_key_3, public_key_4].span(),
            weights: array![4, 5, 2, 1].span(),
            threshold_weight: 5,
        )
        .unwrap();

    // Test:
    let result = dispatcher.check_proof(:msg_hash, proof: array![signature_3].span());
    assert_panic_with_felt_error(:result, expected_error: NOT_ENOUGH_SIGNATURES);

    let result = dispatcher
        .check_proof(:msg_hash, proof: array![signature_3, signature_3, signature_4].span());
    assert_panic_with_felt_error(:result, expected_error: NOT_ENOUGH_SIGNATURES);

    dispatcher.check_proof(:msg_hash, proof: array![signature_2].span()).unwrap();

    dispatcher.check_proof(:msg_hash, proof: array![signature_1, signature_3].span()).unwrap();
    dispatcher
        .check_proof(
            :msg_hash,
            proof: array![zero_signature, signature_4, invalid_signature, signature_1].span(),
        )
        .unwrap();
}

#[test]
#[feature("safe_dispatcher")]
fn test_consortium_flow() {
    // Setup:
    let contract_address = init_contract_with_roles();
    let dispatcher = IConsortiumSafeDispatcher { contract_address };

    // Params:
    let msg_hash = 0x8917d1b016548996625c37d4ac902ccc5951f248ab8466a640a98fa7864de548;
    let proof_hash = 0x4d42ccfdec0c4f7c3d0e1f019c8b33a16db59349d8b8ebacd07c6c5c9105a1b6;

    let secret_key_1 = 0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d9_u256;
    let secret_key_2 = 0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d8_u256;

    let (public_key_1, key_pair_1) = generate_public_key(secret_key: secret_key_1);
    let (public_key_2, key_pair_2) = generate_public_key(secret_key: secret_key_2);

    let signature_1 = key_pair_1.sign(msg_hash).unwrap();
    let signature_2 = key_pair_2.sign(msg_hash).unwrap();
    let signed_proof = key_pair_1.sign(proof_hash).unwrap();

    cheat_caller_address_once(:contract_address, caller_address: APP_GOVERNOR);
    dispatcher
        .set_initial_validator_set(
            epoch: 1,
            public_keys: array![public_key_1].span(),
            weights: array![10].span(),
            threshold_weight: 10,
        )
        .unwrap();

    // Test:

    // Check proof with both signatures.
    dispatcher.check_proof(:msg_hash, proof: array![signature_1].span()).unwrap();

    let result = dispatcher.check_proof(:msg_hash, proof: array![signature_2].span());
    assert_panic_with_felt_error(:result, expected_error: NOT_ENOUGH_SIGNATURES);

    dispatcher
        .set_next_validator_set(
            epoch: 2,
            public_keys: array![public_key_2].span(),
            weights: array![1].span(),
            threshold_weight: 1,
            height: 1234321,
            proof: array![signed_proof].span(),
        )
        .unwrap();

    // Check proof with both signatures.
    let result = dispatcher.check_proof(:msg_hash, proof: array![signature_1].span());
    assert_panic_with_felt_error(:result, expected_error: NOT_ENOUGH_SIGNATURES);

    dispatcher.check_proof(:msg_hash, proof: array![signature_2].span()).unwrap();
}


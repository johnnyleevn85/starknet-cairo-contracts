use lbtc_bascule::interface::{IBasculeDispatcher, IBasculeDispatcherTrait};
use lbtc_testing::utils::bascule::*;
use snforge_std::{EventSpyAssertionsTrait, spy_events};
use starkware_utils::components::pausable::interface::{
    IPausableDispatcher, IPausableDispatcherTrait,
};
use starkware_utils_testing::constants as testing_constants;
use starkware_utils_testing::test_utils::cheat_caller_address_once;

#[test]
fn test_bascule_constructor() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let max_deposits = bascule.get_max_deposits();
    assert_eq!(max_deposits, 20); // Assuming 20 is the default value set during deployment.

    let deposit_reporter_registered = bascule.is_deposit_reporter(constants::DEPOSIT_REPORTER);
    let withdrawal_validator_registered = bascule
        .is_withdrawal_validator(constants::WITHDRAWAL_VALIDATOR);
    let pauser_registered = bascule.is_pauser(constants::PAUSER);

    assert_eq!(deposit_reporter_registered, true);
    assert_eq!(withdrawal_validator_registered, true);
    assert_eq!(pauser_registered, true);
}

#[test]
fn test_update_validation_threshold() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };
    let new_threshold = bascule.get_validation_threshold() + 10;

    let validation_guardian = 'VALIDATION_GUARDIAN'.try_into().unwrap();
    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.register_validation_guardian(validation_guardian);

    cheat_caller_address_once(bascule_address, validation_guardian);
    bascule.update_validation_threshold(new_threshold);

    let updated_threshold = bascule.get_validation_threshold();
    assert_eq!(updated_threshold, new_threshold);

    let new_threshold = bascule.get_validation_threshold() - 10;

    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.update_validation_threshold(new_threshold);

    let updated_threshold = bascule.get_validation_threshold();
    assert_eq!(updated_threshold, new_threshold);
}

#[test]
fn test_double_update_validation_threshold_with_registered_validation_guardian() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };
    let new_threshold = bascule.get_validation_threshold() + 10;

    let validation_guardian = 'VALIDATION_GUARDIAN'.try_into().unwrap();
    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.register_validation_guardian(validation_guardian);

    cheat_caller_address_once(bascule_address, validation_guardian);
    bascule.update_validation_threshold(new_threshold);

    let updated_threshold = bascule.get_validation_threshold();
    assert_eq!(updated_threshold, new_threshold);

    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.register_validation_guardian(validation_guardian);

    let new_threshold = bascule.get_validation_threshold() + 10;

    cheat_caller_address_once(bascule_address, validation_guardian);
    bascule.update_validation_threshold(new_threshold);

    let updated_threshold = bascule.get_validation_threshold();
    assert_eq!(updated_threshold, new_threshold);
}
#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_double_update_validation_threshold() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };
    let new_threshold = bascule.get_validation_threshold() + 10;

    let validation_guardian = 'VALIDATION_GUARDIAN'.try_into().unwrap();
    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.register_validation_guardian(validation_guardian);

    cheat_caller_address_once(bascule_address, validation_guardian);
    bascule.update_validation_threshold(new_threshold);

    let updated_threshold = bascule.get_validation_threshold();
    assert_eq!(updated_threshold, new_threshold);

    cheat_caller_address_once(bascule_address, validation_guardian);
    bascule.update_validation_threshold(new_threshold + 10);
}

#[test]
fn test_set_max_deposits() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let new_max_deposits = 50;
    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.set_max_deposits(new_max_deposits);

    let updated_max_deposits = bascule.get_max_deposits();
    assert_eq!(updated_max_deposits, new_max_deposits);
}

#[test]
fn test_report_deposits() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let deposit_ids = array![1_u256, 2_u256, 3_u256].span();
    let deposit_ids_len = deposit_ids.len();
    let report_id = 123_u256;
    let mut spy = spy_events();
    cheat_caller_address_once(bascule_address, constants::DEPOSIT_REPORTER);
    bascule.report_deposits(:report_id, :deposit_ids);
    spy
        .assert_emitted(
            @array![
                (
                    bascule_address,
                    lbtc_bascule::bascule::bascule::Event::DepositsReported(
                        lbtc_bascule::events::DepositsReported {
                            report_id, num_deposits: deposit_ids_len,
                        },
                    ),
                ),
            ],
        );
}


#[test]
fn test_validate_withdrawal() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let report_id = 1;

    cheat_caller_address_once(bascule_address, constants::DEPOSIT_REPORTER);
    bascule.report_deposits(:report_id, deposit_ids: array![constants::DEPOSIT_ID].span());

    let mut spy = spy_events();
    cheat_caller_address_once(bascule_address, constants::WITHDRAWAL_VALIDATOR);
    bascule
        .validate_withdrawal(
            to_chain: constants::TO_CHAIN,
            recipient: constants::RECIPIENT,
            withdrawal_amount: constants::WITHDRAWAL_AMOUNT,
            tx_id: constants::TX_ID,
            vout: constants::VOUT,
        );
    spy
        .assert_emitted(
            @array![
                (
                    bascule_address,
                    lbtc_bascule::bascule::bascule::Event::WithdrawalValidated(
                        lbtc_bascule::events::WithdrawalValidated {
                            deposit_id: constants::DEPOSIT_ID,
                            withdrawal_amount: constants::WITHDRAWAL_AMOUNT,
                        },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(
    expected: "AlreadyWithdrawn; deposit_id: 94125989962170320294909168232359226434604048150384425340428952718810141678005, withdrawal_amount: 184950000",
)]
fn test_validate_double_withdrawal() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let new_threshold = bascule.get_validation_threshold() + 2 * constants::WITHDRAWAL_AMOUNT;

    let validation_guardian = 'VALIDATION_GUARDIAN'.try_into().unwrap();
    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.register_validation_guardian(validation_guardian);

    cheat_caller_address_once(bascule_address, validation_guardian);
    bascule.update_validation_threshold(new_threshold);

    cheat_caller_address_once(bascule_address, constants::WITHDRAWAL_VALIDATOR);
    bascule
        .validate_withdrawal(
            to_chain: constants::TO_CHAIN,
            recipient: constants::RECIPIENT,
            withdrawal_amount: constants::WITHDRAWAL_AMOUNT,
            tx_id: constants::TX_ID,
            vout: constants::VOUT,
        );

    cheat_caller_address_once(bascule_address, constants::WITHDRAWAL_VALIDATOR);
    bascule
        .validate_withdrawal(
            to_chain: constants::TO_CHAIN,
            recipient: constants::RECIPIENT,
            withdrawal_amount: constants::WITHDRAWAL_AMOUNT,
            tx_id: constants::TX_ID,
            vout: constants::VOUT,
        );
}

#[test]
#[should_panic(
    expected: "WithdrawalFailedValidation; deposit_id: 94125989962170320294909168232359226434604048150384425340428952718810141678005, withdrawal_amount: 184950000",
)]
fn test_validate_withdrawal_above_threshold() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    cheat_caller_address_once(bascule_address, constants::WITHDRAWAL_VALIDATOR);
    bascule
        .validate_withdrawal(
            to_chain: constants::TO_CHAIN,
            recipient: constants::RECIPIENT,
            withdrawal_amount: constants::WITHDRAWAL_AMOUNT,
            tx_id: constants::TX_ID,
            vout: constants::VOUT,
        );
}

#[test]
fn test_successful_validate_withdrawal_not_reported() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };
    let new_threshold = bascule.get_validation_threshold() + 2 * constants::WITHDRAWAL_AMOUNT;

    let validation_guardian = 'VALIDATION_GUARDIAN'.try_into().unwrap();
    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.register_validation_guardian(validation_guardian);

    cheat_caller_address_once(bascule_address, validation_guardian);
    bascule.update_validation_threshold(new_threshold);

    let mut spy = spy_events();
    cheat_caller_address_once(bascule_address, constants::WITHDRAWAL_VALIDATOR);
    bascule
        .validate_withdrawal(
            to_chain: constants::TO_CHAIN,
            recipient: constants::RECIPIENT,
            withdrawal_amount: constants::WITHDRAWAL_AMOUNT,
            tx_id: constants::TX_ID,
            vout: constants::VOUT,
        );
    spy
        .assert_emitted(
            @array![
                (
                    bascule_address,
                    lbtc_bascule::bascule::bascule::Event::WithdrawalNotValidated(
                        lbtc_bascule::events::WithdrawalNotValidated {
                            deposit_id: constants::DEPOSIT_ID,
                            withdrawal_amount: constants::WITHDRAWAL_AMOUNT,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_report_reported_deposits() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let deposit_ids = array![1_u256, 2_u256, 3_u256].span();
    let report_id = 123_u256;
    cheat_caller_address_once(bascule_address, constants::DEPOSIT_REPORTER);
    bascule.report_deposits(:report_id, :deposit_ids);

    let mut spy = spy_events();
    cheat_caller_address_once(bascule_address, constants::DEPOSIT_REPORTER);
    bascule.report_deposits(:report_id, :deposit_ids);
    spy
        .assert_emitted(
            @array![
                (
                    bascule_address,
                    lbtc_bascule::bascule::bascule::Event::DepositAlreadyReported(
                        lbtc_bascule::events::DepositAlreadyReported { deposit_id: 1_u256 },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: 'BAD_DEPOSIT_REPORT')]
fn test_report_deposits_oversize_len() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let new_max_deposits = 4;
    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.set_max_deposits(new_max_deposits);

    let deposit_ids = array![1_u256, 2_u256, 3_u256, 4_u256, 5_u256].span();
    let report_id = 123_u256;
    cheat_caller_address_once(bascule_address, constants::DEPOSIT_REPORTER);
    bascule.report_deposits(:report_id, :deposit_ids);
}

#[test]
fn test_register_and_remove_deposit_reporter() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let new_deposit_reporter = 'NEW_DEPOSIT_REPORTER'.try_into().unwrap();
    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.register_deposit_reporter(new_deposit_reporter);

    let new_deposit_reporter_registered = bascule.is_deposit_reporter(new_deposit_reporter);
    assert_eq!(new_deposit_reporter_registered, true);

    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.remove_deposit_reporter(new_deposit_reporter);

    let new_deposit_reporter_registered = bascule.is_deposit_reporter(new_deposit_reporter);
    assert_eq!(new_deposit_reporter_registered, false);
}

#[test]
fn test_register_and_remove_withdrawal_validator() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let new_withdrawal_validator = 'NEW_WITHDRAWAL_VALIDATOR'.try_into().unwrap();
    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.register_withdrawal_validator(new_withdrawal_validator);

    let new_withdrawal_validator_registered = bascule
        .is_withdrawal_validator(new_withdrawal_validator);
    assert_eq!(new_withdrawal_validator_registered, true);

    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.remove_withdrawal_validator(new_withdrawal_validator);

    let new_withdrawal_validator_registered = bascule
        .is_withdrawal_validator(new_withdrawal_validator);
    assert_eq!(new_withdrawal_validator_registered, false);
}

#[test]
fn test_register_and_remove_validation_guardian() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let new_validation_guardian = 'NEW_VALIDATION_GUARDIAN'.try_into().unwrap();
    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.register_validation_guardian(new_validation_guardian);

    let new_validation_guardian_registered = bascule
        .is_validation_guardian(new_validation_guardian);
    assert_eq!(new_validation_guardian_registered, true);

    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.remove_validation_guardian(new_validation_guardian);

    let new_validation_guardian_registered = bascule
        .is_validation_guardian(new_validation_guardian);
    assert_eq!(new_validation_guardian_registered, false);
}

#[test]
fn test_register_and_remove_pauser() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let new_pauser = 'NEW_PAUSER'.try_into().unwrap();
    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.register_pauser(new_pauser);

    let new_pauser_registered = bascule.is_pauser(new_pauser);
    assert_eq!(new_pauser_registered, true);

    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.remove_pauser(new_pauser);

    let new_pauser_registered = bascule.is_pauser(new_pauser);
    assert_eq!(new_pauser_registered, false);
}

#[test]
#[should_panic(expected: 'INVALID_ZERO_ADDRESS')]
fn test_register_deposit_reporter_with_invalid_zero_address() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let new_deposit_reporter = 0.try_into().unwrap();
    cheat_caller_address_once(bascule_address, testing_constants::GOVERNANCE_ADMIN);
    bascule.register_deposit_reporter(new_deposit_reporter);
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_register_deposit_reporter_with_invalid_role() {
    let bascule_address = init_bascule();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let new_deposit_reporter = 'NEW_DEPOSIT_REPORTER'.try_into().unwrap();
    bascule.register_deposit_reporter(new_deposit_reporter);
}

#[test]
fn test_pause_unpause() {
    let bascule_address = init_bascule();
    let pausable = IPausableDispatcher { contract_address: bascule_address };

    cheat_caller_address_once(bascule_address, constants::PAUSER);
    pausable.pause();

    let is_paused = pausable.is_paused();
    assert_eq!(is_paused, true);

    cheat_caller_address_once(bascule_address, constants::PAUSER);
    pausable.unpause();

    let is_paused = pausable.is_paused();
    assert_eq!(is_paused, false);
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_pause_with_invalid_role() {
    let bascule_address = init_bascule();
    let pausable = IPausableDispatcher { contract_address: bascule_address };

    pausable.pause();
}

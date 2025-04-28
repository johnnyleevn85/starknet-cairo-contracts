use lbtc_bascule::interface::{IBasculeDispatcher, IBasculeDispatcherTrait};
use lbtc_testing::utils::bascule::*;
use snforge_std::{EventSpyAssertionsTrait, spy_events};
use starkware_utils_testing::constants as testing_constants;
use starkware_utils_testing::test_utils::cheat_caller_address_once;

#[test]
fn test_bascule_constructor() {
    let bascule_address = init_bascule_with_roles();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let max_deposits = bascule.get_max_deposits();
    assert_eq!(max_deposits, 20); // Assuming 20 is the default value set during deployment.
}

#[test]
fn test_update_validation_threshold() {
    let bascule_address = init_bascule_with_roles();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };
    let old_threshold = bascule.get_validation_threshold();
    let new_threshold = old_threshold + 10;

    cheat_caller_address_once(bascule_address, testing_constants::APP_GOVERNOR);
    bascule.update_validation_threshold(new_threshold);

    let updated_threshold = bascule.get_validation_threshold();
    assert_eq!(updated_threshold, new_threshold);
}

#[test]
fn test_set_max_deposits() {
    let bascule_address = init_bascule_with_roles();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let new_max_deposits = 50;
    cheat_caller_address_once(bascule_address, testing_constants::APP_GOVERNOR);
    bascule.set_max_deposits(new_max_deposits);

    let updated_max_deposits = bascule.get_max_deposits();
    assert_eq!(updated_max_deposits, new_max_deposits);
}

#[test]
fn test_report_deposits() {
    let bascule_address = init_bascule_with_roles();
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    let deposit_ids = array![1_u256, 2_u256, 3_u256].span();
    let deposit_ids_len = deposit_ids.len();
    let report_id = 123_u256;
    let mut spy = spy_events();
    cheat_caller_address_once(bascule_address, testing_constants::OPERATOR);
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

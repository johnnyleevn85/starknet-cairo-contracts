use lbtc_testing::utils::stake_and_bake::{*, init_stake_and_bake_with_roles};
use starkware_utils_testing::constants as testing_constants;
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use crate::interface::{IStakeAndBakeDispatcher, IStakeAndBakeDispatcherTrait};
use crate::tests::test_utils::*;


#[test]
fn test_stake_and_bake_set_fee() {
    let stake_and_bake_address = init_stake_and_bake_with_roles();
    let stake_and_bake = IStakeAndBakeDispatcher { contract_address: stake_and_bake_address };

    let fee = stake_and_bake.get_stake_and_bake_fee();
    assert_eq!(fee, 5);

    cheat_caller_address_once(
        contract_address: stake_and_bake_address, caller_address: testing_constants::OPERATOR,
    );
    stake_and_bake.set_fee(10);
    let fee = stake_and_bake.get_stake_and_bake_fee();
    assert_eq!(fee, 10);
}

#[test]
fn test_stake_and_bake_set_depositor() {
    let stake_and_bake_address = init_stake_and_bake_with_roles();
    let stake_and_bake = IStakeAndBakeDispatcher { contract_address: stake_and_bake_address };

    let depositor = stake_and_bake.get_stake_and_bake_depositor();
    assert_eq!(depositor, constants::VAULT);

    cheat_caller_address_once(
        contract_address: stake_and_bake_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    let new_vault = constants::NEW_VAULT;
    stake_and_bake.set_depositor(new_vault);
    let depositor = stake_and_bake.get_stake_and_bake_depositor();
    assert_eq!(depositor, new_vault);
}


use core::num::traits::Zero;
use lbtc_bridge::bridge::bridge;
use lbtc_bridge::interface::{IBridgeDispatcher, IBridgeDispatcherTrait};
use lbtc_bridge::tests::test_utils::*;
use snforge_std::{EventSpyAssertionsTrait, spy_events};
use starkware_utils_testing::{constants as testing_constants, test_utils};


#[test]
fn test_bridge_change_consortium() {
    let bridge_address = init_bridge_with_roles();
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let old_consortium = bridge.get_consortium();
    assert!(old_consortium.is_non_zero());
    test_utils::cheat_caller_address_once(
        contract_address: bridge_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    let mut spy = spy_events();
    let new_consortium = testing_constants::DUMMY_ADDRESS;
    bridge.change_consortium(new_consortium);
    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    lbtc_bridge::bridge::bridge::Event::ConsortiumChanged(
                        lbtc_bridge::events::ConsortiumChanged { old_consortium, new_consortium },
                    ),
                ),
            ],
        );
    assert_eq!(bridge.get_consortium(), new_consortium);
}

#[test]
fn test_bridge_get_consortium() {
    let bridge_address = init_bridge_with_roles();
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let consortium = bridge.get_consortium();
    assert_eq!(consortium, constants::CONSORTIUM);
}

#[test]
fn test_bridge_change_treasury() {
    let bridge_address = init_bridge_with_roles();
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let old_treasury = bridge.get_treasury();
    assert!(old_treasury.is_non_zero());
    test_utils::cheat_caller_address_once(
        contract_address: bridge_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    let new_treasury = testing_constants::DUMMY_ADDRESS;
    let mut spy = spy_events();
    bridge.change_treasury(new_treasury);
    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    lbtc_bridge::bridge::bridge::Event::TreasuryChanged(
                        lbtc_bridge::events::TreasuryChanged { old_treasury, new_treasury },
                    ),
                ),
            ],
        );
    assert_eq!(bridge.get_treasury(), new_treasury);
}

#[test]
fn test_bridge_get_treasury() {
    let bridge_address = init_bridge_with_roles();
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let treasury = bridge.get_treasury();
    assert_eq!(treasury, constants::TREASURY);
}

#[test]
fn test_bridge_change_burn_commission() {
    let bridge_address = init_bridge_with_roles();
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let old_burn_commission = bridge.get_burn_commission();
    assert!(old_burn_commission.is_non_zero());
    test_utils::cheat_caller_address_once(
        contract_address: bridge_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    let mut spy = spy_events();
    let new_burn_commission = constants::BURN_COMMISSION * 2;
    bridge.change_burn_commission(new_burn_commission);
    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    lbtc_bridge::bridge::bridge::Event::BurnCommissionChanged(
                        lbtc_bridge::events::BurnCommissionChanged {
                            old_burn_commission, new_burn_commission,
                        },
                    ),
                ),
            ],
        );
    assert_eq!(bridge.get_burn_commission(), new_burn_commission);
}

#[test]
fn test_bridge_get_burn_commission() {
    let bridge_address = init_bridge_with_roles();
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let burn_commission = bridge.get_burn_commission();
    assert_eq!(burn_commission, constants::BURN_COMMISSION);
}

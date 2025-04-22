use core::num::traits::Zero;
use core::sha256::compute_sha256_byte_array;
use lbtc_bridge::bitcoin_utils::DEFAULT_DUST_FEE_RATE;
use lbtc_bridge::bridge::bridge;
use lbtc_bridge::interface::{IBridgeDispatcher, IBridgeDispatcherTrait};
use lbtc_bridge::utils::{build_deposit_payload, build_deposit_payload_with_selector};
use lbtc_testing::utils::bridge::*;
use snforge_std::{EventSpyAssertionsTrait, spy_events};
use starkware_utils::math::utils::u256_from_u32_array;
use starkware_utils_testing::{constants as testing_constants, test_utils};

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

#[test]
fn test_calculate_deposit_btc_sha256_hash() {
    // These fields are taken from this tx:
    // https://etherscan.io/tx/0x49f935f83533f509510c0cd387a44d67342a89e3f9048a6327d5a3e36695a005.
    let payload_without_selector = build_deposit_payload(
        to_chain: 0x1,
        recipient: 0xbe6afb3a18bbb8f35e2a12c330d0e37daebab802.try_into().unwrap(),
        amount: 0xb061cf0,
        tx_id: 0x8b881e06005aff8dd8768600d785d9d0027b65896368dbf3bd6fbf13ae8fb9d1_u256,
        vout: 0x0,
    );
    let payload: ByteArray = build_deposit_payload_with_selector(
        deposit_payload: @payload_without_selector,
    );
    let res: u256 = u256_from_u32_array(compute_sha256_byte_array(arr: @payload));
    assert_eq!(res, 0xb0586b1a69730b27c74028669b4b4746052bd4d8250fe0a2d1a74d63218def57);
}

#[test]
fn test_change_dust_fee_rate() {
    let bridge_address = init_bridge_with_roles();
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let mut spy = spy_events();
    let old_rate = DEFAULT_DUST_FEE_RATE;

    let dust_fee_rate = bridge.get_dust_fee_rate();
    assert_eq!(dust_fee_rate, old_rate);

    let new_rate = 13;
    test_utils::cheat_caller_address_once(
        contract_address: bridge_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    bridge.change_dust_fee_rate(:new_rate);
    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    lbtc_bridge::bridge::bridge::Event::DustFeeRateChanged(
                        lbtc_bridge::events::DustFeeRateChanged { old_rate, new_rate },
                    ),
                ),
            ],
        );
}
#[test]
fn test_toggle_withdrawals() {
    let bridge_address = init_bridge_with_roles();
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    let mut spy = spy_events();

    test_utils::cheat_caller_address_once(
        contract_address: bridge_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    bridge.enable_withdrawals();
    assert_eq!(bridge.is_withdrawals_enabled(), true);
    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    lbtc_bridge::bridge::bridge::Event::WithdrawalsEnabled(
                        lbtc_bridge::events::WithdrawalsEnabled { is_withdrawals_enabled: true },
                    ),
                ),
            ],
        );

    test_utils::cheat_caller_address_once(
        contract_address: bridge_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    bridge.disable_withdrawals();
    assert_eq!(bridge.is_withdrawals_enabled(), false);
    spy
        .assert_emitted(
            @array![
                (
                    bridge_address,
                    lbtc_bridge::bridge::bridge::Event::WithdrawalsEnabled(
                        lbtc_bridge::events::WithdrawalsEnabled { is_withdrawals_enabled: false },
                    ),
                ),
            ],
        );
}

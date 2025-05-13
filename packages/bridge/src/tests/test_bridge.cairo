use core::num::traits::Zero;
use core::sha256::compute_sha256_byte_array;
use lbtc_bridge::bitcoin_utils::DEFAULT_DUST_FEE_RATE;
use lbtc_bridge::bridge::bridge;
use lbtc_bridge::interface::{IBridgeDispatcher, IBridgeDispatcherTrait};
use lbtc_bridge::utils::{build_deposit_payload, build_deposit_payload_with_selector};
use lbtc_consortium::interface::{IConsortiumDispatcher, IConsortiumDispatcherTrait};
use lbtc_testing::utils::bridge::*;
use lbtc_testing::utils::consortium::init_contract_with_roles as init_consortium_with_roles;
use snforge_std::{EventSpyAssertionsTrait, spy_events};
use starkware_utils::math::utils::u256_from_u32_array;
use starkware_utils_testing::test_utils::cheat_caller_address_once;
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

#[test]
fn test_successful_deposit_payload_check_proof() {
    // Setup:
    let contract_address = init_consortium_with_roles();
    let dispatcher = IConsortiumDispatcher { contract_address };

    // Params:
    let public_key = (
        0x663730d52c5ae76aa45189e3a007240da11fca011a6ed9eb427ddcd72a806114_u256,
        0x48f1dc776b895b5c7ab2914437f255b2002001821d271ca9aa2bed6819078c1e_u256,
    );
    /// make sure that hash of payload not used before
    /// need to check new sha256 hash and legacy keccak256 from payload without selector
    /// 2 checks made to prevent migration of contract state
    let legacy_payload = build_deposit_payload(
        to_chain: 0x04000000000000000000000000000000000000000000534e5f5345504f4c4941_u256,
        recipient: 0x07adab2c6aa4691884d0b4d8ee1877106df238f70814ef1276f96539ca10dd84
            .try_into()
            .unwrap(),
        amount: 10000,
        tx_id: 0xc267cbbf16f0930753afe02243940607ae67e15d0e3942b216b8900dc54f50b5_u256,
        vout: 0,
    );

    let payload: ByteArray = build_deposit_payload_with_selector(deposit_payload: @legacy_payload);

    let msg_hash: u256 = u256_from_u32_array(compute_sha256_byte_array(arr: @payload));

    assert_eq!(0x6b92e1d08a951b031ab6a54733b8d2dada5b21460fc61fd5cc61d0b20e65332e_u256, msg_hash);
    let r = 0x9d94ba8cc5d6746e70d1e570e69e479ccc5e27d3d6fb0a16c8b02eb93290346d_u256;
    let s = 0x508ffc9e106aaa68d8c684fe66eaada65f1d3daeb85a9e0e4814db2cc2279ff5_u256;
    let signature = (r, s);

    cheat_caller_address_once(:contract_address, caller_address: testing_constants::APP_GOVERNOR);
    dispatcher
        .set_initial_validator_set(
            public_keys: array![public_key].span(), weights: array![1].span(), threshold_weight: 1,
        );

    // Test:
    dispatcher.check_proof(:msg_hash, proof: array![signature].span());
    // Test passes if `check_proof` did not panic.
}

fn test_calculate_unstake_request_amount() {
    let bridge_address = init_bridge_with_roles();
    let bridge = IBridgeDispatcher { contract_address: bridge_address };

    // Test 1:
    // This `script_pub_key` was taken from:
    // https://etherscan.io/tx/0x8ec3474737cff92ee35bcda61cd215e12f36cdc8aff0f399e6576beead96d2cf
    let mut script_pub_key: ByteArray = Default::default();
    script_pub_key
        .append_word(0x5120bbc0b6e1493ef28d47c14cf5deac3210fee748d57f6fe77ecaa58db0ed, 31);
    script_pub_key.append_word(0x1e1285, 3);
    let (amount_after_fee, is_above_dust) = bridge
        .calculate_unstake_request_amount(:script_pub_key, amount: 20000);
    assert_eq!(is_above_dust, true);
    assert_eq!(amount_after_fee, 19999);

    // Test 2:
    // This `script_pub_key` was taken from
    // https://etherscan.io/tx/0x95be457ca836d7d6baf233453b5fc3d317df2e986baac5b8330921dac289fb52.
    let mut script_pub_key: ByteArray = Default::default();
    script_pub_key.append_word(0x00141882fd00f4c211282d9bab64650676c1c9ed2cb4, 22);
    let (amount_after_fee, is_above_dust) = bridge
        .calculate_unstake_request_amount(:script_pub_key, amount: 300);
    assert_eq!(is_above_dust, false);
    assert_eq!(amount_after_fee, 299);

    // Test 3:
    // This `script_pub_key` was taken from:
    // https://etherscan.io/tx/0x8ec3474737cff92ee35bcda61cd215e12f36cdc8aff0f399e6576beead96d2cf
    let mut script_pub_key: ByteArray = Default::default();
    script_pub_key
        .append_word(0x5120bbc0b6e1493ef28d47c14cf5deac3210fee748d57f6fe77ecaa58db0ed, 31);
    script_pub_key.append_word(0x1e1285, 3);
    let (amount_after_fee, is_above_dust) = bridge
        .calculate_unstake_request_amount(:script_pub_key, amount: 1);
    assert_eq!(is_above_dust, false);
    assert_eq!(amount_after_fee, 0);
}

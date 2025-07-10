use core::num::traits::Zero;
use core::sha256::compute_sha256_byte_array;
use lbtc_asset_router::asset_router::asset_router;
use lbtc_asset_router::bitcoin_utils::DEFAULT_DUST_FEE_RATE;
use lbtc_asset_router::errors;
use lbtc_asset_router::interface::{
    IAssetRouterDispatcher, IAssetRouterDispatcherTrait, IAssetRouterSafeDispatcher,
    IAssetRouterSafeDispatcherTrait,
};
use lbtc_asset_router::utils::build_deposit_payload_with_selector;
use lbtc_bascule::interface::{IBasculeDispatcher, IBasculeDispatcherTrait};
use lbtc_consortium::interface::{IConsortiumDispatcher, IConsortiumDispatcherTrait};
use lbtc_testing::utils::asset_router::*;
use lbtc_testing::utils::bascule::constants::DEPOSIT_REPORTER;
use lbtc_testing::utils::consortium::{
    generate_public_key, init_contract_with_roles as init_consortium_with_roles,
};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::signature::secp256k1_curve::{Secp256k1CurveKeyPairImpl, Secp256k1CurveSignerImpl};
use snforge_std::{EventSpyAssertionsTrait, spy_events};
use starknet::ContractAddress;
use starkware_utils::interfaces::mintable_token::{
    IMintableTokenDispatcher, IMintableTokenDispatcherTrait,
};
use starkware_utils::math::utils::u256_from_u32_array;
use starkware_utils_testing::constants as testing_constants;
use starkware_utils_testing::test_utils::{
    assert_panic_with_error, assert_panic_with_felt_error, cheat_caller_address_once,
};

#[test]
fn test_get_consortium() {
    let asset_router_address = init_asset_router_with_roles();
    let asset_router = IAssetRouterDispatcher { contract_address: asset_router_address };
    let consortium = asset_router.get_consortium();
    assert_eq!(consortium, constants::CONSORTIUM);
}

#[test]
fn test_change_treasury() {
    let asset_router_address = init_asset_router_with_roles();
    let asset_router = IAssetRouterDispatcher { contract_address: asset_router_address };
    let old_treasury = asset_router.get_treasury();
    assert!(old_treasury.is_non_zero());
    cheat_caller_address_once(
        contract_address: asset_router_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    let new_treasury = testing_constants::DUMMY_ADDRESS;
    let mut spy = spy_events();
    asset_router.change_treasury(new_treasury);
    spy
        .assert_emitted(
            @array![
                (
                    asset_router_address,
                    lbtc_asset_router::asset_router::asset_router::Event::TreasuryChanged(
                        lbtc_asset_router::events::TreasuryChanged { old_treasury, new_treasury },
                    ),
                ),
            ],
        );
    assert_eq!(asset_router.get_treasury(), new_treasury);
}

#[test]
fn test_get_treasury() {
    let asset_router_address = init_asset_router_with_roles();
    let asset_router = IAssetRouterDispatcher { contract_address: asset_router_address };
    let treasury = asset_router.get_treasury();
    assert_eq!(treasury, constants::TREASURY);
}

#[test]
fn test_change_burn_commission() {
    let asset_router_address = init_asset_router_with_roles();
    let asset_router = IAssetRouterDispatcher { contract_address: asset_router_address };
    let old_burn_commission = asset_router.get_burn_commission();
    assert!(old_burn_commission.is_non_zero());
    cheat_caller_address_once(
        contract_address: asset_router_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    let mut spy = spy_events();
    let new_burn_commission = constants::BURN_COMMISSION * 2;
    asset_router.change_burn_commission(new_burn_commission);
    spy
        .assert_emitted(
            @array![
                (
                    asset_router_address,
                    lbtc_asset_router::asset_router::asset_router::Event::BurnCommissionChanged(
                        lbtc_asset_router::events::BurnCommissionChanged {
                            old_burn_commission, new_burn_commission,
                        },
                    ),
                ),
            ],
        );
    assert_eq!(asset_router.get_burn_commission(), new_burn_commission);
}

#[test]
fn test_get_burn_commission() {
    let asset_router_address = init_asset_router_with_roles();
    let asset_router = IAssetRouterDispatcher { contract_address: asset_router_address };
    let burn_commission = asset_router.get_burn_commission();
    assert_eq!(burn_commission, constants::BURN_COMMISSION);
}

#[test]
fn test_calculate_deposit_btc_sha256_hash() {
    // These fields are taken from this tx:
    // https://etherscan.io/tx/0x49f935f83533f509510c0cd387a44d67342a89e3f9048a6327d5a3e36695a005.
    let to_chain = 0x1;
    let recipient: ContractAddress = 0xbe6afb3a18bbb8f35e2a12c330d0e37daebab802.try_into().unwrap();
    let amount = 0xb061cf0;
    let tx_id = 0x8b881e06005aff8dd8768600d785d9d0027b65896368dbf3bd6fbf13ae8fb9d1_u256;
    let vout = 0x0;

    let payload: ByteArray = build_deposit_payload_with_selector(
        :to_chain, :recipient, :amount, :tx_id, :vout,
    );
    let res: u256 = u256_from_u32_array(compute_sha256_byte_array(arr: @payload));
    assert_eq!(res, 0xb0586b1a69730b27c74028669b4b4746052bd4d8250fe0a2d1a74d63218def57);
}

#[test]
fn test_change_dust_fee_rate() {
    let asset_router_address = init_asset_router_with_roles();
    let asset_router = IAssetRouterDispatcher { contract_address: asset_router_address };
    let mut spy = spy_events();
    let old_rate = DEFAULT_DUST_FEE_RATE;

    let dust_fee_rate = asset_router.get_dust_fee_rate();
    assert_eq!(dust_fee_rate, old_rate);

    let new_rate = 13;
    cheat_caller_address_once(
        contract_address: asset_router_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    asset_router.change_dust_fee_rate(:new_rate);
    spy
        .assert_emitted(
            @array![
                (
                    asset_router_address,
                    lbtc_asset_router::asset_router::asset_router::Event::DustFeeRateChanged(
                        lbtc_asset_router::events::DustFeeRateChanged { old_rate, new_rate },
                    ),
                ),
            ],
        );
}

#[test]
fn test_toggle_withdrawals() {
    let asset_router_address = init_asset_router_with_roles();
    let asset_router = IAssetRouterDispatcher { contract_address: asset_router_address };
    let mut spy = spy_events();

    cheat_caller_address_once(
        contract_address: asset_router_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    asset_router.enable_withdrawals();
    assert_eq!(asset_router.is_withdrawals_enabled(), true);
    spy
        .assert_emitted(
            @array![
                (
                    asset_router_address,
                    lbtc_asset_router::asset_router::asset_router::Event::WithdrawalsEnabled(
                        lbtc_asset_router::events::WithdrawalsEnabled {
                            is_withdrawals_enabled: true,
                        },
                    ),
                ),
            ],
        );

    cheat_caller_address_once(
        contract_address: asset_router_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    asset_router.disable_withdrawals();
    assert_eq!(asset_router.is_withdrawals_enabled(), false);
    spy
        .assert_emitted(
            @array![
                (
                    asset_router_address,
                    lbtc_asset_router::asset_router::asset_router::Event::WithdrawalsEnabled(
                        lbtc_asset_router::events::WithdrawalsEnabled {
                            is_withdrawals_enabled: false,
                        },
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
    let to_chain = 0x04000000000000000000000000000000000000000000534e5f5345504f4c4941_u256;
    let recipient: ContractAddress =
        0x07adab2c6aa4691884d0b4d8ee1877106df238f70814ef1276f96539ca10dd84
        .try_into()
        .unwrap();
    let amount = 10000;
    let tx_id = 0xc267cbbf16f0930753afe02243940607ae67e15d0e3942b216b8900dc54f50b5_u256;
    let vout = 0;

    let payload: ByteArray = build_deposit_payload_with_selector(
        :to_chain, :recipient, :amount, :tx_id, :vout,
    );

    let msg_hash: u256 = u256_from_u32_array(compute_sha256_byte_array(arr: @payload));

    assert_eq!(0x6b92e1d08a951b031ab6a54733b8d2dada5b21460fc61fd5cc61d0b20e65332e_u256, msg_hash);
    let r = 0x9d94ba8cc5d6746e70d1e570e69e479ccc5e27d3d6fb0a16c8b02eb93290346d_u256;
    let s = 0x508ffc9e106aaa68d8c684fe66eaada65f1d3daeb85a9e0e4814db2cc2279ff5_u256;
    let signature = (r, s);

    cheat_caller_address_once(:contract_address, caller_address: testing_constants::APP_GOVERNOR);
    dispatcher
        .set_initial_validator_set(
            epoch: 1,
            public_keys: array![public_key].span(),
            weights: array![1].span(),
            threshold_weight: 1,
        );

    // Test:
    dispatcher.check_proof(:msg_hash, proof: array![signature].span());
    // Test passes if `check_proof` did not panic.
}

#[test]
fn test_calculate_unstake_request_amount() {
    let asset_router_address = init_asset_router_with_roles();
    let asset_router = IAssetRouterDispatcher { contract_address: asset_router_address };

    // Test 1:
    // This `script_pub_key` was taken from:
    // https://etherscan.io/tx/0x8ec3474737cff92ee35bcda61cd215e12f36cdc8aff0f399e6576beead96d2cf
    let mut script_pub_key: ByteArray = Default::default();
    script_pub_key
        .append_word(0x5120bbc0b6e1493ef28d47c14cf5deac3210fee748d57f6fe77ecaa58db0ed, 31);
    script_pub_key.append_word(0x1e1285, 3);
    let (amount_after_fee, is_above_dust) = asset_router
        .calculate_unstake_request_amount(:script_pub_key, amount: 20000);
    assert_eq!(is_above_dust, true);
    assert_eq!(amount_after_fee, 19999);

    // Test 2:
    // This `script_pub_key` was taken from
    // https://etherscan.io/tx/0x95be457ca836d7d6baf233453b5fc3d317df2e986baac5b8330921dac289fb52.
    let mut script_pub_key: ByteArray = Default::default();
    script_pub_key.append_word(0x00141882fd00f4c211282d9bab64650676c1c9ed2cb4, 22);
    let (amount_after_fee, is_above_dust) = asset_router
        .calculate_unstake_request_amount(:script_pub_key, amount: 295);
    assert_eq!(is_above_dust, false);
    assert_eq!(amount_after_fee, 294);

    // Test 3:
    // This `script_pub_key` was taken from:
    // https://etherscan.io/tx/0x8ec3474737cff92ee35bcda61cd215e12f36cdc8aff0f399e6576beead96d2cf
    let mut script_pub_key: ByteArray = Default::default();
    script_pub_key
        .append_word(0x5120bbc0b6e1493ef28d47c14cf5deac3210fee748d57f6fe77ecaa58db0ed, 31);
    script_pub_key.append_word(0x1e1285, 3);
    let (amount_after_fee, is_above_dust) = asset_router
        .calculate_unstake_request_amount(:script_pub_key, amount: 1);
    assert_eq!(is_above_dust, false);
    assert_eq!(amount_after_fee, 0);
}

#[test]
#[feature("safe_dispatcher")]
fn test_redeem_invalid_scenarios() {
    let (lbtc_address, _, _, asset_router_address) = general_contract_system_deployment();
    let asset_router = IAssetRouterSafeDispatcher { contract_address: asset_router_address };
    let recipient: ContractAddress = testing_constants::DUMMY_ADDRESS;

    // Params:
    // `script_pub_key` was taken from this tx:
    // https://etherscan.io/tx/0x95be457ca836d7d6baf233453b5fc3d317df2e986baac5b8330921dac289fb52.
    let mut script_pub_key: ByteArray = Default::default();
    script_pub_key.append_word(0x00141882fd00f4c211282d9bab64650676c1c9ed2cb4, 22);

    let mut unsupported_script_pub_key: ByteArray = Default::default();
    unsupported_script_pub_key.append_word(0x00141882fd00f4c211282d9bab646506, 16);

    // Test 1: Withdrawals are disabled.
    cheat_caller_for_redeem(:asset_router_address, :lbtc_address, :recipient);
    let result = asset_router.redeem(script_pub_key: script_pub_key.clone(), amount: 290);
    assert_panic_with_felt_error(:result, expected_error: errors::WITHDRAWALS_DISABLED);

    // Enable withdrawals:
    cheat_caller_address_once(
        contract_address: asset_router_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    asset_router.enable_withdrawals().unwrap();

    // Test 2: Amount is below dust limit.
    snforge_std::cheat_caller_address(
        contract_address: lbtc_address,
        caller_address: testing_constants::TOKEN_ADMIN,
        span: snforge_std::CheatSpan::TargetCalls(2),
    );
    let result = asset_router.redeem(script_pub_key: script_pub_key.clone(), amount: 290);
    assert_panic_with_error(:result, expected_error: errors::amount_below_dust_limit(294));

    // Test 3: Amount is above the redeem limit.
    snforge_std::cheat_caller_address(
        contract_address: lbtc_address,
        caller_address: testing_constants::TOKEN_ADMIN,
        span: snforge_std::CheatSpan::TargetCalls(2),
    );
    let result = asset_router.redeem(script_pub_key: script_pub_key.clone(), amount: 300);
    assert_panic_with_felt_error(:result, expected_error: errors::REDEEM_LIMIT_EXCEEDED);

    // Test 4: Script pub key is unsupported.
    // For permissioned mint, and permissioned burn.
    snforge_std::cheat_caller_address(
        contract_address: lbtc_address,
        caller_address: testing_constants::TOKEN_ADMIN,
        span: snforge_std::CheatSpan::TargetCalls(2),
    );
    let result = asset_router.redeem(script_pub_key: unsupported_script_pub_key, amount: 300);
    assert_panic_with_felt_error(:result, expected_error: errors::SCRIPT_PUB_KEY_UNSUPPORTED);

    // Test 5: Amount is less than commission.
    cheat_caller_address_once(
        contract_address: asset_router_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    asset_router.change_burn_commission(constants::BURN_COMMISSION * 100).unwrap();

    snforge_std::cheat_caller_address(
        contract_address: lbtc_address,
        caller_address: testing_constants::TOKEN_ADMIN,
        span: snforge_std::CheatSpan::TargetCalls(2),
    );
    let result = asset_router.redeem(:script_pub_key, amount: 100);
    assert_panic_with_error(:result, expected_error: errors::amount_less_than_commission(100));
}

#[test]
#[feature("safe_dispatcher")]
fn test_mint_invalid_inputs() {
    let asset_router_address = init_asset_router_with_roles();
    let dispatcher = IAssetRouterSafeDispatcher { contract_address: asset_router_address };

    // Params
    let mut minted_amount = 2100000;
    let tx_id = 8825713371439348803474373711484783374832390354312780486399108193461143465930_u256;
    let vout = 0;
    let mut recipient: ContractAddress = 0xbd2d60e98dbe64dc97128ea526b7ebb9035b54b8
        .try_into()
        .unwrap();
    let proof = array![
        (
            0x70e056f659f83d3a7161c83a2c41dc7215805507e2b3c51b0d47e90fc9800533_u256,
            0x635b3f0f45e407b3bbb1330fb303db386fe3d6f8b919c782104d75a525e404a_u256,
        ),
    ]
        .span();

    // Chain ID not corresponds to starknet identifier.
    let mut to_chain = 0x3000000000000000000000000000000000000000000534E5F5345504F4C4941;
    let mut result = dispatcher
        .mint(:to_chain, :recipient, amount: minted_amount, :tx_id, :vout, :proof);
    assert_panic_with_felt_error(:result, expected_error: errors::WRONG_CHAIN_ID);

    // Chain ID not corresponds to tx_id.
    to_chain = 0x4000000000000000000000000000000000000000000534E5F5345504F4C4942;
    result = dispatcher.mint(:to_chain, :recipient, amount: minted_amount, :tx_id, :vout, :proof);
    assert_panic_with_felt_error(:result, expected_error: errors::WRONG_CHAIN_ID);

    to_chain = 0x4000000000000000000000000000000000000000000534E5F5345504F4C4941;
    recipient = 0x0.try_into().unwrap();
    result = dispatcher.mint(:to_chain, :recipient, amount: minted_amount, :tx_id, :vout, :proof);
    assert_panic_with_felt_error(:result, expected_error: errors::INVALID_ZERO_ADDRESS);

    recipient = 0xbd2d60e98dbe64dc97128ea526b7ebb9035b54b8.try_into().unwrap();
    minted_amount = 0;
    result = dispatcher.mint(:to_chain, :recipient, amount: minted_amount, :tx_id, :vout, :proof);
    assert_panic_with_felt_error(:result, expected_error: errors::INVALID_ZERO_AMOUNT);
}

#[test]
#[should_panic(expected: 'PAYLOAD_ALREADY_USED')]
fn test_double_mint() {
    let (_, bascule_address, consortium_address, asset_router_address) =
        general_contract_system_deployment();
    let asset_router = IAssetRouterDispatcher { contract_address: asset_router_address };
    let consortium = IConsortiumDispatcher { contract_address: consortium_address };
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    // Creat public key, and initial validator set:
    let secret_key = 0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d9_u256;
    let (public_key, _) = generate_public_key(:secret_key);

    cheat_caller_address_once(
        contract_address: consortium_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    consortium
        .set_initial_validator_set(
            epoch: 1,
            public_keys: array![public_key].span(),
            weights: array![1].span(),
            threshold_weight: 1,
        );

    // Report deposit:
    let report_id = 0;
    let deposit_ids = array![
        0x132ef74cb644c5aee2d953045946b28e64cb8e57b5c8b72a252ffd1bf2cef9c1_u256,
    ]
        .span();
    cheat_caller_address_once(contract_address: bascule_address, caller_address: DEPOSIT_REPORTER);
    bascule.report_deposits(:report_id, :deposit_ids);

    // Mint:

    let to_chain = 0x400000000000000000000000000000000000000000000000000000000000001;
    let minted_amount = 2100000;
    let tx_id = 8825713371439348803474373711484783374832390354312780486399108193461143465930_u256;
    let vout = 0;
    let recipient: ContractAddress = 0xbd2d60e98dbe64dc97128ea526b7ebb9035b54b8.try_into().unwrap();
    let proof = array![
        (
            0x70e056f659f83d3a7161c83a2c41dc7215805507e2b3c51b0d47e90fc9800533_u256,
            0x635b3f0f45e407b3bbb1330fb303db386fe3d6f8b919c782104d75a525e404a_u256,
        ),
    ]
        .span();

    cheat_caller_for_mint(:asset_router_address);
    asset_router.mint(:to_chain, :recipient, amount: minted_amount, :tx_id, :vout, :proof);

    cheat_caller_for_mint(:asset_router_address);
    asset_router.mint(:to_chain, :recipient, amount: minted_amount, :tx_id, :vout, :proof);
}

#[test]
fn test_contract_getters() {
    let (lbtc_address, bascule_address, consortium_address, asset_router_address) =
        general_contract_system_deployment();
    let asset_router = IAssetRouterDispatcher { contract_address: asset_router_address };

    assert_eq!(asset_router.get_lbtc_token_address(), lbtc_address);
    assert_eq!(asset_router.get_bascule(), bascule_address);
    assert_eq!(asset_router.get_consortium(), consortium_address);
}

#[test]
#[feature("safe_dispatcher")]
fn test_mint_through_different_chain() {
    //Setup:
    let (lbtc_address, bascule_address, consortium_address, asset_router_address) =
        general_contract_system_deployment();
    let asset_router = IAssetRouterSafeDispatcher { contract_address: asset_router_address };
    let consortium = IConsortiumDispatcher { contract_address: consortium_address };
    let bascule = IBasculeDispatcher { contract_address: bascule_address };
    let erc20 = IERC20Dispatcher { contract_address: lbtc_address };
    let lbtc_token = IMintableTokenDispatcher { contract_address: lbtc_address };

    // Creat public key, and initial validator set:
    let secret_key = 0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d9_u256;
    let (public_key, _) = generate_public_key(:secret_key);

    cheat_caller_address_once(
        contract_address: consortium_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    consortium
        .set_initial_validator_set(
            epoch: 1,
            public_keys: array![public_key].span(),
            weights: array![1].span(),
            threshold_weight: 1,
        );

    // Report deposit:
    let report_id = 0;
    let deposit_ids = array![
        0x132ef74cb644c5aee2d953045946b28e64cb8e57b5c8b72a252ffd1bf2cef9c1_u256,
    ]
        .span();
    cheat_caller_address_once(contract_address: bascule_address, caller_address: DEPOSIT_REPORTER);
    bascule.report_deposits(:report_id, :deposit_ids);

    // Mint:

    // Tx:
    // https://etherscan.io/tx/0x5996abdbfbd1e1d5f456586a8b5933e321adf66494d2e4b92e2cb873457d3008
    let to_chain = 0x400000000000000000000000000000000000000000000000000000000000001;
    let minted_amount = 2100000;
    let total_amount = 2 * minted_amount;
    let tx_id = 8825713371439348803474373711484783374832390354312780486399108193461143465930_u256;
    let vout = 0;
    let recipient: ContractAddress = 0xbd2d60e98dbe64dc97128ea526b7ebb9035b54b8.try_into().unwrap();
    let proof = array![
        (
            0x70e056f659f83d3a7161c83a2c41dc7215805507e2b3c51b0d47e90fc9800533_u256,
            0x635b3f0f45e407b3bbb1330fb303db386fe3d6f8b919c782104d75a525e404a_u256,
        ),
    ]
        .span();

    // Minting through other chain:
    cheat_caller_address_once(
        contract_address: lbtc_address, caller_address: testing_constants::TOKEN_ADMIN,
    );
    lbtc_token.permissioned_mint(account: recipient, amount: minted_amount);

    // Minting through lbtc asset_router.
    cheat_caller_for_mint(:asset_router_address);
    asset_router.mint(:to_chain, :recipient, amount: minted_amount, :tx_id, :vout, :proof).unwrap();

    //Withdraw:
    // Enable withdrawals.
    cheat_caller_address_once(
        contract_address: asset_router_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    asset_router.enable_withdrawals().unwrap();

    // Test:
    let balance = erc20.balance_of(recipient);
    assert_eq!(balance, total_amount);

    // `script_pub_key` was taken from this tx:
    // https://etherscan.io/tx/0x95be457ca836d7d6baf233453b5fc3d317df2e986baac5b8330921dac289fb52.
    let mut script_pub_key: ByteArray = Default::default();
    script_pub_key.append_word(0x00141882fd00f4c211282d9bab64650676c1c9ed2cb4, 22);

    // Try to redeem through the asset_router all the amount the recipient has.
    cheat_caller_for_redeem(:asset_router_address, :lbtc_address, :recipient);
    let result = asset_router.redeem(script_pub_key: script_pub_key.clone(), amount: total_amount);
    assert_panic_with_felt_error(:result, expected_error: errors::REDEEM_LIMIT_EXCEEDED);

    cheat_caller_for_redeem(:asset_router_address, :lbtc_address, :recipient);
    asset_router.redeem(script_pub_key: script_pub_key.clone(), amount: minted_amount).unwrap();

    cheat_caller_address_once(
        contract_address: lbtc_address, caller_address: testing_constants::TOKEN_ADMIN,
    );
    lbtc_token.permissioned_burn(account: recipient, amount: minted_amount);

    // Check that no more tokens are left for the recipient.
    assert_eq!(erc20.total_supply(), 1);
    assert_eq!(erc20.balance_of(recipient), 0);
}

#[test]
fn test_mint_then_partial_redeem() {
    let (lbtc_address, bascule_address, consortium_address, asset_router_address) =
        general_contract_system_deployment();
    let asset_router = IAssetRouterDispatcher { contract_address: asset_router_address };
    let consortium = IConsortiumDispatcher { contract_address: consortium_address };
    let bascule = IBasculeDispatcher { contract_address: bascule_address };
    let token = IERC20Dispatcher { contract_address: lbtc_address };

    // Creat public key, and initial validator set:
    let secret_key = 0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d9_u256;
    let (public_key, _) = generate_public_key(:secret_key);

    cheat_caller_address_once(
        contract_address: consortium_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    consortium
        .set_initial_validator_set(
            epoch: 1,
            public_keys: array![public_key].span(),
            weights: array![1].span(),
            threshold_weight: 1,
        );

    // Report deposit:
    let report_id = 0;
    let deposit_ids = array![
        0x132ef74cb644c5aee2d953045946b28e64cb8e57b5c8b72a252ffd1bf2cef9c1_u256,
    ]
        .span();
    cheat_caller_address_once(contract_address: bascule_address, caller_address: DEPOSIT_REPORTER);
    bascule.report_deposits(:report_id, :deposit_ids);

    // Mint:

    // Tx:
    // https://etherscan.io/tx/0x5996abdbfbd1e1d5f456586a8b5933e321adf66494d2e4b92e2cb873457d3008
    let to_chain = 0x400000000000000000000000000000000000000000000000000000000000001;
    let minted_amount = 2100000;
    let burned_amount = 1000;
    let tx_id = 8825713371439348803474373711484783374832390354312780486399108193461143465930_u256;
    let vout = 0;
    let recipient: ContractAddress = 0xbd2d60e98dbe64dc97128ea526b7ebb9035b54b8.try_into().unwrap();
    let proof = array![
        (
            0x70e056f659f83d3a7161c83a2c41dc7215805507e2b3c51b0d47e90fc9800533_u256,
            0x635b3f0f45e407b3bbb1330fb303db386fe3d6f8b919c782104d75a525e404a_u256,
        ),
    ]
        .span();

    cheat_caller_for_mint(:asset_router_address);
    asset_router.mint(:to_chain, :recipient, amount: minted_amount, :tx_id, :vout, :proof);

    //Withdraw:
    // Enable withdrawals.
    cheat_caller_address_once(
        contract_address: asset_router_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    asset_router.enable_withdrawals();

    // Test:
    let balance = token.balance_of(recipient);
    assert_eq!(balance, minted_amount.into());

    // `script_pub_key` was taken from this tx:
    // https://etherscan.io/tx/0x95be457ca836d7d6baf233453b5fc3d317df2e986baac5b8330921dac289fb52.
    let mut script_pub_key: ByteArray = Default::default();
    script_pub_key.append_word(0x00141882fd00f4c211282d9bab64650676c1c9ed2cb4, 22);
    cheat_caller_for_redeem(:asset_router_address, :lbtc_address, :recipient);
    asset_router.redeem(:script_pub_key, amount: burned_amount);

    // Check:
    assert_eq!(token.balance_of(recipient), (minted_amount - burned_amount).into());
    assert_eq!(token.balance_of(asset_router.get_treasury()), constants::BURN_COMMISSION.into());
    assert_eq!(
        token.total_supply(),
        (minted_amount - burned_amount + constants::BURN_COMMISSION.into()).into(),
    );
}

#[test]
fn test_flow_multi_mint_single_redeem() {
    let (lbtc_address, bascule_address, consortium_address, asset_router_address) =
        general_contract_system_deployment();
    let asset_router = IAssetRouterDispatcher { contract_address: asset_router_address };
    let consortium = IConsortiumDispatcher { contract_address: consortium_address };
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    // Creat public key, and initial validator set:
    let secret_key = 0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d9_u256;
    let (public_key, key_pair) = generate_public_key(:secret_key);

    cheat_caller_address_once(
        contract_address: consortium_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    consortium
        .set_initial_validator_set(
            epoch: 1,
            public_keys: array![public_key].span(),
            weights: array![1].span(),
            threshold_weight: 1,
        );

    // Report deposit:
    let report_id = 0;
    let deposit_ids = array![
        0x18148af6cca30164e176a553ffdbfbcc3e0d3242ef7136f56f3104ac14940ba8_u256,
        0x502473324cbe2a75611f4099e01a006f5e3895333ec6e1f2f0424daf1283823d_u256,
    ]
        .span();
    cheat_caller_address_once(contract_address: bascule_address, caller_address: DEPOSIT_REPORTER);
    bascule.report_deposits(:report_id, :deposit_ids);

    // Mint:

    let to_chain = 0x400000000000000000000000000000000000000000000000000000000000001;
    let minted_amount_1 = 100;
    let minted_amount_2 = 200;
    let tx_id = 63111984368071406484652863285634728739123633370987300322098412345060920113617_u256;
    let vout = 0;
    let recipient: ContractAddress = 0xbe6afb3a18bbb8f35e2a12c330d0e37daebab802.try_into().unwrap();
    let signature_1 = key_pair
        .sign(0x3d4b66cf028ca3d02517a38744702738ae4e8aee43abc034d1c9eea271234bcc)
        .unwrap();
    let signature_2 = key_pair
        .sign(0x6b84523284c4815f3fc425589c085610876d012b2dfee2417d9d499600103777)
        .unwrap();
    let proof = array![signature_1, signature_2].span();

    snforge_std::cheat_chain_id(
        contract_address: asset_router_address,
        chain_id: 1,
        span: snforge_std::CheatSpan::TargetCalls(1),
    );
    asset_router.mint(:to_chain, :recipient, amount: minted_amount_1, :tx_id, :vout, :proof);

    snforge_std::cheat_chain_id(
        contract_address: asset_router_address,
        chain_id: 1,
        span: snforge_std::CheatSpan::TargetCalls(1),
    );
    asset_router.mint(:to_chain, :recipient, amount: minted_amount_2, :tx_id, :vout, :proof);

    // Withdraw:

    cheat_caller_address_once(
        contract_address: asset_router_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    asset_router.enable_withdrawals();

    let mut script_pub_key: ByteArray = Default::default();
    script_pub_key.append_word(0x00141882fd00f4c211282d9bab64650676c1c9ed2cb4, 22);

    cheat_caller_address_once(contract_address: asset_router_address, caller_address: recipient);
    asset_router.redeem(:script_pub_key, amount: 300);

    // Check:
    let token = IERC20Dispatcher { contract_address: lbtc_address };
    assert_eq!(token.balance_of(recipient), 0);
}


#[test]
fn test_flow_single_mint_multi_redeem() {
    let (lbtc_address, bascule_address, consortium_address, asset_router_address) =
        general_contract_system_deployment();
    let asset_router = IAssetRouterDispatcher { contract_address: asset_router_address };
    let consortium = IConsortiumDispatcher { contract_address: consortium_address };
    let bascule = IBasculeDispatcher { contract_address: bascule_address };

    // Creat public key, and initial validator set:
    let secret_key = 0x21a30c0bdaa3b425e17a062bfdf5b8ecaed4e2d3ab4b30b0774472d4621081d9_u256;
    let (public_key, key_pair) = generate_public_key(:secret_key);

    cheat_caller_address_once(
        contract_address: consortium_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    consortium
        .set_initial_validator_set(
            epoch: 1,
            public_keys: array![public_key].span(),
            weights: array![1].span(),
            threshold_weight: 1,
        );

    // Report deposit:
    let report_id = 0;
    let deposit_ids = array![
        0x76bc2931bf66f91460de40a1208dfca876c0c6e2470e9ea868d1a6b7f38e5f7e_u256,
    ]
        .span();
    cheat_caller_address_once(contract_address: bascule_address, caller_address: DEPOSIT_REPORTER);
    bascule.report_deposits(:report_id, :deposit_ids);

    // Mint:

    let to_chain = 0x400000000000000000000000000000000000000000000000000000000000001;
    let minted_amount = 1000;
    let tx_id = 63111984368071406484652863285634728739123633370987300322098412345060920113617_u256;
    let vout = 0;
    let recipient: ContractAddress = 0xbe6afb3a18bbb8f35e2a12c330d0e37daebab802.try_into().unwrap();
    let signature = key_pair
        .sign(0x4d7cc26f5e14d11a487152adc5cd0498fa41263f0e383c8c44e2d2740ef2c284)
        .unwrap();
    let proof = array![signature].span();

    snforge_std::cheat_chain_id(
        contract_address: asset_router_address,
        chain_id: 1,
        span: snforge_std::CheatSpan::TargetCalls(1),
    );
    asset_router.mint(:to_chain, :recipient, amount: minted_amount, :tx_id, :vout, :proof);

    // Withdraw:

    cheat_caller_address_once(
        contract_address: asset_router_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    asset_router.enable_withdrawals();

    let mut script_pub_key: ByteArray = Default::default();
    script_pub_key.append_word(0x00141882fd00f4c211282d9bab64650676c1c9ed2cb4, 22);

    cheat_caller_address_once(contract_address: asset_router_address, caller_address: recipient);
    asset_router.redeem(script_pub_key: script_pub_key.clone(), amount: 300);

    cheat_caller_address_once(contract_address: asset_router_address, caller_address: recipient);
    asset_router.redeem(:script_pub_key, amount: 700);

    // Check:
    let token = IERC20Dispatcher { contract_address: lbtc_address };
    assert_eq!(token.balance_of(recipient), 0);
}

use core::num::traits::{Bounded, Pow};
use erc4626::interface::{IERC4626Dispatcher, IERC4626DispatcherTrait};
use lbtc_testing::utils::manual_strategy::constants as strategy_constants;
use lbtc_testing::utils::vault::*;
use lbtc_vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use starknet::ContractAddress;
use starkware_utils_testing::constants as testing_constants;
use starkware_utils_testing::test_utils::cheat_caller_address_once;

#[test]
fn test_vault_constructor() {
    let (_, _, vault_address) = init_vault_with_roles();
    let vault = IVaultDispatcher { contract_address: vault_address };

    let deposit_limit = vault.get_deposit_limit();
    assert_eq!(deposit_limit, constants::DEPOSIT_LIMIT);
}

/// Deposit tests.

#[test]
fn test_vault_deposit() {
    // Setup:
    let (token_address, strategy_address, vault_address) = init_vault_with_roles();
    let vault_erc4626 = IERC4626Dispatcher { contract_address: vault_address };
    let vault_erc20 = IERC20Dispatcher { contract_address: vault_address };
    let lbtc_erc20 = IERC20Dispatcher { contract_address: token_address };
    let strategy_erc20 = IERC20Dispatcher { contract_address: strategy_address };

    let user: ContractAddress = 'USER_ADDRESS'.try_into().unwrap();
    let multi_sig = strategy_constants::MULTI_SIG_ADDRESS;
    let fee_recipient = constants::FEE_RECIPIENT;

    let deposit_amount = 100;
    // Shares:assets ratio is 1:1_000_000_000.
    let total_shares = 100_000_000_000;
    // Fee is 4%.
    let fee_shares = 4_000_000_000;
    let user_shares = total_shares - fee_shares;

    fund_user(:token_address, :user, contract_address: vault_address, amount: deposit_amount);
    assert_eq!(lbtc_erc20.balance_of(account: user), deposit_amount);
    assert_eq!(vault_erc4626.total_assets(), 0);

    // Test:
    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    let deposit_result = vault_erc4626.deposit(assets: deposit_amount, receiver: user);
    assert_eq!(deposit_result, user_shares);

    // Checks:
    assert_eq!(lbtc_erc20.balance_of(account: multi_sig), deposit_amount);
    assert_eq!(lbtc_erc20.balance_of(account: vault_address), 0);
    assert_eq!(lbtc_erc20.balance_of(account: user), 0);

    assert_eq!(vault_erc20.total_supply(), total_shares);
    assert_eq!(vault_erc20.balance_of(account: user), user_shares);
    assert_eq!(vault_erc20.balance_of(account: fee_recipient), fee_shares);

    assert_eq!(strategy_erc20.total_supply(), total_shares);
    assert_eq!(strategy_erc20.balance_of(account: vault_address), total_shares);
}

#[test]
fn test_vault_preview_deposit() {
    // Setup:
    let (token_address, _, vault_address) = init_vault_with_roles();
    let vault_erc4626 = IERC4626Dispatcher { contract_address: vault_address };

    let user: ContractAddress = 'USER_ADDRESS'.try_into().unwrap();
    let fee_recipient = constants::FEE_RECIPIENT;

    fund_user(:token_address, :user, contract_address: vault_address, amount: Bounded::MAX / 2);
    fund_user(
        :token_address,
        user: fee_recipient,
        contract_address: vault_address,
        amount: Bounded::MAX / 2,
    );

    let deposit_amounts = array![
        13_u256,
        99_u256,
        100_u256,
        26 * (10_u256.pow(6)),
        4 + (10_u256.pow(6)),
        1 + 7 * (10_u256.pow(6)),
    ];
    let deposit_shares_results = array![
        12480000000,
        95040000000,
        96 * constants::ASSETS_2_SHARES,
        24960000 * constants::ASSETS_2_SHARES,
        960003840000000,
        6720000960000000,
    ];

    for i in 0..deposit_amounts.len() {
        cheat_caller_address_once(contract_address: vault_address, caller_address: user);
        let shares_preview_deposit = vault_erc4626.preview_deposit(assets: *deposit_amounts[i]);
        assert_eq!(shares_preview_deposit, *deposit_shares_results[i]);

        cheat_caller_address_once(contract_address: vault_address, caller_address: user);
        let deposit_shares = vault_erc4626.deposit(assets: *deposit_amounts[i], receiver: user);
        assert_eq!(shares_preview_deposit, deposit_shares);

        // Test when fee recipient is the caller.
        cheat_caller_address_once(contract_address: vault_address, caller_address: fee_recipient);
        let shares_preview_deposit = vault_erc4626.preview_deposit(assets: *deposit_amounts[i]);
        assert_eq!(shares_preview_deposit, *deposit_amounts[i] * constants::ASSETS_2_SHARES);

        cheat_caller_address_once(contract_address: vault_address, caller_address: fee_recipient);
        let deposit_shares = vault_erc4626
            .deposit(assets: *deposit_amounts[i], receiver: fee_recipient);
        assert_eq!(shares_preview_deposit, deposit_shares);
    }
}

// Invalid deposit tests:

#[test]
#[should_panic(expected: 'ERC20: insufficient allowance')]
fn test_vault_invalid_deposit_insufficient_allowance() {
    let (token_address, _, vault_address) = init_vault_with_roles();
    let erc4626 = IERC4626Dispatcher { contract_address: vault_address };
    let user: ContractAddress = 'USER_ADDRESS'.try_into().unwrap();

    let deposit_amount = 1_000_000_000;
    fund_user(:token_address, :user, contract_address: vault_address, amount: deposit_amount - 1);

    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    erc4626.deposit(assets: deposit_amount, receiver: vault_address);
}

#[test]
#[should_panic(expected: 'SHARES_BELOW_DUST')]
fn test_vault_invalid_deposit_low_shares() {
    let (token_address, _, vault_address) = init_vault_with_roles();
    let erc4626 = IERC4626Dispatcher { contract_address: vault_address };
    let user: ContractAddress = 'USER_ADDRESS'.try_into().unwrap();

    let deposit_amount = 0;
    fund_user(:token_address, :user, contract_address: vault_address, amount: deposit_amount);

    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    erc4626.deposit(assets: deposit_amount, receiver: vault_address);
}

#[test]
#[should_panic(expected: 'ERC4626: exceeds max deposit')]
fn test_vault_invalid_deposit_above_deposit_limit() {
    let (token_address, _, vault_address) = init_vault_with_roles();
    let erc4626 = IERC4626Dispatcher { contract_address: vault_address };

    let user: ContractAddress = 'USER_ADDRESS'.try_into().unwrap();
    let deposit_amount = 1_000_000_000_000_000_001; // DEPOSIT_LIMIT + 1.
    fund_user(:token_address, :user, contract_address: vault_address, amount: deposit_amount);

    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    erc4626.deposit(assets: deposit_amount, receiver: vault_address);
}

/// Withdraw tests.

#[test]
fn test_vault_withdraw() {
    // Setup:
    let (lbtc_token_address, manual_strategy_address, vault_address) = init_vault_with_roles();
    let vault_erc4626 = IERC4626Dispatcher { contract_address: vault_address };
    let vault_erc20 = IERC20Dispatcher { contract_address: vault_address };
    let lbtc_erc20 = IERC20Dispatcher { contract_address: lbtc_token_address };
    let strategy_erc20 = IERC20Dispatcher { contract_address: manual_strategy_address };

    let user: ContractAddress = 'USER_ADDRESS'.try_into().unwrap();
    let multi_sig = strategy_constants::MULTI_SIG_ADDRESS;
    let fee_recipient = constants::FEE_RECIPIENT;

    let deposit_amount = 100;
    // Shares:assets ratio is 1:1_000_000_000.
    let deposit_total_shares = 100_000_000_000;
    // Fee is 4%.
    let deposit_fee_shares = 4_000_000_000;

    fund_user(
        token_address: lbtc_token_address,
        :user,
        contract_address: vault_address,
        amount: deposit_amount,
    );

    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    vault_erc4626.deposit(assets: deposit_amount, receiver: user);

    // Partial withdraw phase:

    let partial_withdraw_amount = 49;
    let partial_withdraw_amount_in_shares = 49_000_000_000;
    let partial_withdraw_fee_shares = 1_000_000_000;
    let mut user_shares = deposit_total_shares
        - deposit_fee_shares
        - partial_withdraw_amount_in_shares
        - partial_withdraw_fee_shares;

    // Test:
    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    let withdraw_result = vault_erc4626
        .withdraw(assets: partial_withdraw_amount, receiver: user, owner: user);
    assert_eq!(withdraw_result, partial_withdraw_amount_in_shares + partial_withdraw_fee_shares);

    // Checks:
    assert_eq!(lbtc_erc20.balance_of(account: multi_sig), deposit_amount - partial_withdraw_amount);
    assert_eq!(lbtc_erc20.balance_of(account: vault_address), 0);
    assert_eq!(lbtc_erc20.balance_of(account: user), partial_withdraw_amount);

    assert_eq!(vault_erc20.balance_of(account: vault_address), 0);
    assert_eq!(
        vault_erc20.balance_of(account: fee_recipient),
        deposit_fee_shares + partial_withdraw_fee_shares,
    );
    assert_eq!(vault_erc20.balance_of(account: user), user_shares);

    assert_eq!(
        strategy_erc20.balance_of(account: vault_address),
        deposit_total_shares - partial_withdraw_amount_in_shares,
    );

    assert_eq!(vault_erc4626.total_assets(), deposit_amount - partial_withdraw_amount);
    assert_eq!(
        vault_erc20.total_supply(), deposit_total_shares - partial_withdraw_amount_in_shares,
    );

    // Full withdraw phase:

    let full_withdraw_amount = 45;
    let full_withdraw_amount_in_shares = 45_000_000_000;
    let full_withdraw_fee_shares = 918_367_347;
    user_shares -= full_withdraw_amount_in_shares + full_withdraw_fee_shares;

    // Test:
    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    let withdraw_result = vault_erc4626
        .withdraw(assets: full_withdraw_amount, receiver: user, owner: user);
    assert_eq!(withdraw_result, full_withdraw_amount_in_shares + full_withdraw_fee_shares);

    // Checks:
    assert_eq!(
        lbtc_erc20.balance_of(account: multi_sig),
        deposit_amount - partial_withdraw_amount - full_withdraw_amount,
    );
    assert_eq!(lbtc_erc20.balance_of(account: vault_address), 0);
    assert_eq!(
        lbtc_erc20.balance_of(account: user), partial_withdraw_amount + full_withdraw_amount,
    );

    assert_eq!(vault_erc20.balance_of(account: vault_address), 0);
    assert_eq!(
        vault_erc20.balance_of(account: fee_recipient),
        deposit_fee_shares + partial_withdraw_fee_shares + full_withdraw_fee_shares,
    );
    assert_eq!(vault_erc20.balance_of(account: user), user_shares);

    assert_eq!(
        strategy_erc20.balance_of(account: vault_address),
        deposit_total_shares - partial_withdraw_amount_in_shares - full_withdraw_amount_in_shares,
    );

    assert_eq!(
        vault_erc4626.total_assets(),
        deposit_amount - partial_withdraw_amount - full_withdraw_amount,
    );
    assert_eq!(
        vault_erc20.total_supply(),
        deposit_total_shares - partial_withdraw_amount_in_shares - full_withdraw_amount_in_shares,
    );
}

#[test]
#[should_panic(expected: 'SHARES_BELOW_DUST')]
fn test_vault_withdraw_below_dust() {
    // Setup:
    let (lbtc_token_address, _, vault_address) = init_vault_with_roles();
    let vault_erc4626 = IERC4626Dispatcher { contract_address: vault_address };

    let user: ContractAddress = 'USER_ADDRESS'.try_into().unwrap();
    let deposit_amount = 10;

    fund_user(
        token_address: lbtc_token_address,
        :user,
        contract_address: vault_address,
        amount: deposit_amount,
    );

    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    vault_erc4626.deposit(assets: deposit_amount, receiver: user);

    let withdraw_amount = 0;

    // Test:
    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    vault_erc4626.withdraw(assets: withdraw_amount, receiver: user, owner: user);
}

#[test]
#[should_panic(expected: 'WITHDRAWALS_PAUSED')]
fn test_vault_withdrawals_paused() {
    // Setup:
    let (lbtc_token_address, _, vault_address) = init_vault_with_roles();
    let vault_erc4626 = IERC4626Dispatcher { contract_address: vault_address };
    let vault_dispatcher = IVaultDispatcher { contract_address: vault_address };

    let user: ContractAddress = 'USER_ADDRESS'.try_into().unwrap();
    let deposit_amount = 10;

    fund_user(
        token_address: lbtc_token_address,
        :user,
        contract_address: vault_address,
        amount: deposit_amount,
    );

    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    vault_erc4626.deposit(assets: deposit_amount, receiver: user);

    let withdraw_amount = 1;

    // Test:
    cheat_caller_address_once(
        contract_address: vault_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    vault_dispatcher.disable_withdrawals();
    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    vault_erc4626.withdraw(assets: withdraw_amount, receiver: user, owner: user);
}

#[test]
fn test_vault_redeem() {
    // Setup:
    let (lbtc_token_address, manual_strategy_address, vault_address) = init_vault_with_roles();
    let vault_erc4626 = IERC4626Dispatcher { contract_address: vault_address };
    let vault_erc20 = IERC20Dispatcher { contract_address: vault_address };
    let lbtc_erc20 = IERC20Dispatcher { contract_address: lbtc_token_address };
    let strategy_erc20 = IERC20Dispatcher { contract_address: manual_strategy_address };

    let user: ContractAddress = 'USER_ADDRESS'.try_into().unwrap();
    let multi_sig = strategy_constants::MULTI_SIG_ADDRESS;
    let fee_recipient = constants::FEE_RECIPIENT;

    let deposit_amount = 100;
    // Shares:assets ratio is 1:1_000_000_000.
    let deposit_total_shares = 100_000_000_000;
    // Fee is 4%.
    let deposit_fee_shares = 4_000_000_000;

    fund_user(
        token_address: lbtc_token_address,
        :user,
        contract_address: vault_address,
        amount: deposit_amount,
    );

    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    vault_erc4626.deposit(assets: deposit_amount, receiver: user);

    // Partial redeem phase:

    let partial_redeem_amount = 50_000_000_000;
    let partial_redeem_fee = 1_000_000_000;
    let partial_redeem_amount_in_assets = 50;
    let partial_redeem_fee_assets = 1;
    let user_shares = deposit_total_shares - deposit_fee_shares - partial_redeem_amount;

    // Test:
    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    let redeem_result = vault_erc4626
        .redeem(shares: partial_redeem_amount, receiver: user, owner: user);
    assert_eq!(redeem_result, partial_redeem_amount_in_assets - partial_redeem_fee_assets);

    // Checks:
    assert_eq!(
        lbtc_erc20.balance_of(account: multi_sig),
        deposit_amount - (partial_redeem_amount_in_assets - partial_redeem_fee_assets),
    );
    assert_eq!(lbtc_erc20.balance_of(account: vault_address), 0);
    assert_eq!(
        lbtc_erc20.balance_of(account: user),
        partial_redeem_amount_in_assets - partial_redeem_fee_assets,
    );

    assert_eq!(vault_erc20.balance_of(account: vault_address), 0);
    assert_eq!(
        vault_erc20.balance_of(account: fee_recipient), deposit_fee_shares + partial_redeem_fee,
    );
    assert_eq!(vault_erc20.balance_of(account: user), user_shares);

    assert_eq!(
        strategy_erc20.balance_of(account: vault_address),
        deposit_total_shares - (partial_redeem_amount - partial_redeem_fee),
    );

    assert_eq!(
        vault_erc4626.total_assets(),
        deposit_amount - (partial_redeem_amount_in_assets - partial_redeem_fee_assets),
    );
    assert_eq!(
        vault_erc20.total_supply(),
        deposit_total_shares - (partial_redeem_amount - partial_redeem_fee),
    );

    // Complete redeem phase:

    let full_redeem_amount = 46_000_000_000;
    let full_redeem_fee = 920_000_000;
    let full_redeem_amount_in_assets = 46;
    let full_redeem_fee_assets = 1;

    // Test:
    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    let redeem_result = vault_erc4626
        .redeem(shares: full_redeem_amount, receiver: user, owner: user);
    assert_eq!(redeem_result, full_redeem_amount_in_assets - full_redeem_fee_assets);

    // Checks:
    assert_eq!(
        lbtc_erc20.balance_of(account: multi_sig),
        deposit_amount
            - (partial_redeem_amount_in_assets - partial_redeem_fee_assets)
            - (full_redeem_amount_in_assets - full_redeem_fee_assets),
    );
    assert_eq!(lbtc_erc20.balance_of(account: vault_address), 0);
    assert_eq!(
        lbtc_erc20.balance_of(account: user),
        partial_redeem_amount_in_assets
            - partial_redeem_fee_assets
            + full_redeem_amount_in_assets
            - full_redeem_fee_assets,
    );

    assert_eq!(vault_erc20.balance_of(account: vault_address), 0);
    assert_eq!(
        vault_erc20.balance_of(account: fee_recipient),
        deposit_fee_shares + partial_redeem_fee + full_redeem_fee,
    );
    assert_eq!(vault_erc20.balance_of(account: user), 0);

    assert_eq!(
        strategy_erc20.balance_of(account: vault_address),
        deposit_total_shares
            - (partial_redeem_amount - partial_redeem_fee)
            - (full_redeem_amount - full_redeem_fee)
            + 80_000_000,
    );

    assert_eq!(
        vault_erc4626.total_assets(),
        deposit_amount
            - (partial_redeem_amount_in_assets - partial_redeem_fee_assets)
            - (full_redeem_amount_in_assets - full_redeem_fee_assets),
    );
    assert_eq!(
        vault_erc20.total_supply(),
        deposit_total_shares
            - (partial_redeem_amount - partial_redeem_fee)
            - (full_redeem_amount - full_redeem_fee),
    );
}
fn test_vault_deposit_withdraw_fee() {
    // Setup:
    let (token_address, _, vault_address) = init_vault_with_roles();
    let vault_erc4626 = IERC4626Dispatcher { contract_address: vault_address };
    let vault_erc20 = IERC20Dispatcher { contract_address: vault_address };
    let lbtc_erc20 = IERC20Dispatcher { contract_address: token_address };

    let user: ContractAddress = 'USER_ADDRESS'.try_into().unwrap();
    let fee_recipient = constants::FEE_RECIPIENT;
    let multi_sig = strategy_constants::MULTI_SIG_ADDRESS;
    let deposit_amount = 10_u256.pow(18);
    let shares_after_deposit_fee = 960 * 10_u256.pow(24); // deducting 4% deposit fee.
    let assets_after_fees = 940800
        * 10_u256.pow(12); // deducting 4% deposit fee and 2% withdraw fee.
    let fees_in_assets = 59200 * 10_u256.pow(12);

    fund_user(:token_address, :user, contract_address: vault_address, amount: deposit_amount);
    assert_eq!(lbtc_erc20.balance_of(account: user), deposit_amount);
    assert_eq!(vault_erc4626.total_assets(), 0);

    // Test:
    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    let user_shares = vault_erc4626.deposit(assets: deposit_amount, receiver: user);
    assert_eq!(user_shares, shares_after_deposit_fee);

    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    let user_assets = vault_erc4626.redeem(shares: user_shares, receiver: user, owner: user);
    assert_eq!(user_assets, assets_after_fees);
    assert_eq!(lbtc_erc20.balance_of(account: multi_sig), deposit_amount - assets_after_fees);

    let max_shares = vault_erc4626.max_redeem(owner: fee_recipient);
    assert_eq!(max_shares, fees_in_assets * 10_u256.pow(9)); // The fee shares.

    cheat_caller_address_once(contract_address: vault_address, caller_address: fee_recipient);
    vault_erc4626.redeem(shares: max_shares, receiver: fee_recipient, owner: fee_recipient);

    // Checks:
    assert_eq!(lbtc_erc20.balance_of(account: fee_recipient), fees_in_assets);
    assert_eq!(vault_erc20.total_supply(), 0); // All the shares were redeemed.
}


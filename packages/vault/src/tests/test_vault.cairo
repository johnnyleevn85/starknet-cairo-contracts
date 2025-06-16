use erc4626::interface::{IERC4626Dispatcher, IERC4626DispatcherTrait};
use lbtc_testing::utils::manual_strategy::constants as strategy_constants;
use lbtc_testing::utils::vault::*;
use lbtc_vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use starknet::ContractAddress;
use starkware_utils_testing::test_utils::cheat_caller_address_once;

#[test]
fn test_vault_constructor() {
    let (_, _, vault_address) = init_vault_with_roles();
    let vault = IVaultDispatcher { contract_address: vault_address };

    let deposit_limit = vault.get_deposit_limit();
    assert_eq!(deposit_limit, constants::DEPOSIT_LIMIT);
}

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


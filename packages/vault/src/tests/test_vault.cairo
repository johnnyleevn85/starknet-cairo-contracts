use lbtc_testing::utils::vault::*;
use lbtc_vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
use openzeppelin::token::erc20::extensions::erc4626::interface::{
    IERC4626Dispatcher, IERC4626DispatcherTrait,
};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use starknet::ContractAddress;
use starkware_utils_testing::test_utils::cheat_caller_address_once;

#[test]
fn test_vault_constructor() {
    let (_, vault_address) = init_vault_with_roles();
    let vault = IVaultDispatcher { contract_address: vault_address };

    let deposit_limit = vault.get_deposit_limit();
    assert_eq!(deposit_limit, constants::DEPOSIT_LIMIT);
}

#[test]
fn test_vault_deposit() {
    // Setup:
    let (token_address, vault_address) = init_vault_with_roles();
    let erc4626 = IERC4626Dispatcher { contract_address: vault_address };
    let vault_erc20 = IERC20Dispatcher { contract_address: vault_address };
    let lbtc_erc20 = IERC20Dispatcher { contract_address: token_address };

    let user: ContractAddress = 'USER_ADDRESS'.try_into().unwrap();
    let deposit_amount = 1_000_000_000;
    let amount_after_fee = 960_000_000;

    fund_user(:token_address, :user, contract_address: vault_address, amount: deposit_amount);
    assert_eq!(lbtc_erc20.balance_of(account: user), deposit_amount);
    assert_eq!(erc4626.total_assets(), 0);

    // Test:
    cheat_caller_address_once(contract_address: vault_address, caller_address: user);
    let deposit_result = erc4626.deposit(assets: deposit_amount, receiver: vault_address);
    assert_eq!(deposit_result, amount_after_fee);

    // Checks:
    assert_eq!(lbtc_erc20.balance_of(account: vault_address), deposit_amount);
    assert_eq!(lbtc_erc20.balance_of(account: user), 0);
    assert_eq!(erc4626.total_assets(), deposit_amount);
    assert_eq!(vault_erc20.balance_of(account: vault_address), amount_after_fee);
}


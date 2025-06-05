use lbtc_testing::utils::manual_strategy::init_manual_strategy_with_roles;
use lbtc_testing::utils::token::init_token_with_roles;
use openzeppelin::token::erc20::erc20::ERC20Component::InternalImpl;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::deployment::declare_and_deploy;
use starknet::ContractAddress;
use starkware_utils::interfaces::mintable_token::{
    IMintableTokenDispatcher, IMintableTokenDispatcherTrait,
};
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use starkware_utils_testing::{constants as testing_constants, test_utils};

pub mod constants {
    use super::*;

    pub const UPGRADE_DELAY: u64 = 0;
    pub const TOKEN_ADDRESS: ContractAddress = 'LBTC_TOKEN_ADDRESS'.try_into().unwrap();
    pub const STRATEGY_ADDRESS: ContractAddress = 'MANUAL_STRATEGY_ADDRESS'.try_into().unwrap();
    pub const DEPOSIT_LIMIT: u256 = 1_000_000_000_000_000_000;
    pub const FEE_RECIPIENT: ContractAddress = 'FEE_RECIPIENT'.try_into().unwrap();
    pub const DEPOSIT_FEE: u128 = 400; // 4%.
    pub const WITHDRAW_FEE: u128 = 200;
    pub const PROTOCOL_FEE: u128 = 250;
    pub const PERFORMANCE_FEE: (u256, u256, u64) = (0, 500, 1000);
}

fn deploy_vault(
    token_address: ContractAddress, strategy_address: ContractAddress,
) -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(testing_constants::GOVERNANCE_ADMIN);
    calldata.append_serde(constants::UPGRADE_DELAY);
    calldata.append_serde(token_address);
    calldata.append_serde(strategy_address);
    calldata.append_serde(constants::DEPOSIT_LIMIT);
    calldata.append_serde(constants::FEE_RECIPIENT);
    calldata.append_serde(constants::DEPOSIT_FEE);
    calldata.append_serde(constants::WITHDRAW_FEE);
    calldata.append_serde(constants::PROTOCOL_FEE);
    calldata.append_serde(array![constants::PERFORMANCE_FEE].span());

    declare_and_deploy("vault", calldata)
}

pub fn init_vault_with_roles() -> (ContractAddress, ContractAddress, ContractAddress) {
    let lbtc_token_address = init_token_with_roles();
    let manual_strategy_address = init_manual_strategy_with_roles(
        token_address: lbtc_token_address,
    );

    let vault_address = deploy_vault(
        token_address: lbtc_token_address, strategy_address: manual_strategy_address,
    );
    test_utils::set_default_roles(
        contract: vault_address, governance_admin: testing_constants::GOVERNANCE_ADMIN,
    );
    // Set Vault as operator in Manual Strategy.
    test_utils::set_account_as_operator(
        contract: manual_strategy_address,
        account: vault_address,
        app_role_admin: testing_constants::APP_ROLE_ADMIN,
    );
    (lbtc_token_address, manual_strategy_address, vault_address)
}

pub fn fund_user(
    token_address: ContractAddress,
    user: ContractAddress,
    contract_address: ContractAddress,
    amount: u256,
) {
    let dispatcher = IMintableTokenDispatcher { contract_address: token_address };
    cheat_caller_address_once(
        contract_address: token_address, caller_address: testing_constants::TOKEN_ADMIN,
    );
    dispatcher.permissioned_mint(account: user, :amount);

    let erc20_dispatcher = IERC20Dispatcher { contract_address: token_address };
    cheat_caller_address_once(contract_address: token_address, caller_address: user);
    erc20_dispatcher.approve(spender: contract_address, :amount);
}

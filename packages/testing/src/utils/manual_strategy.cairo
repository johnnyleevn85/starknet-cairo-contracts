use core::num::traits::Bounded;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::deployment::declare_and_deploy;
use starknet::ContractAddress;
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use starkware_utils_testing::{constants as testing_constants, test_utils};

pub mod constants {
    use super::*;

    pub const UPGRADE_DELAY: u64 = 0;
    pub const TOKEN_ADDRESS: ContractAddress = 'TOKEN_ADDRESS'.try_into().unwrap();
    pub const MULTI_SIG_ADDRESS: ContractAddress = 'MULTI_SIG_ADDRESS'.try_into().unwrap();
}

fn deploy_manual_strategy(token_address: ContractAddress) -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(testing_constants::GOVERNANCE_ADMIN);
    calldata.append_serde(constants::UPGRADE_DELAY);
    calldata.append_serde(token_address);
    calldata.append_serde(constants::MULTI_SIG_ADDRESS);

    declare_and_deploy("manual_strategy", calldata)
}

pub fn init_manual_strategy_with_roles(token_address: ContractAddress) -> ContractAddress {
    let manual_strategy_address = deploy_manual_strategy(:token_address);
    test_utils::set_default_roles(
        contract: manual_strategy_address, governance_admin: testing_constants::GOVERNANCE_ADMIN,
    );

    // Infinite approval from MultiSig to ManualStrategy to spend LBTC tokens.
    cheat_caller_address_once(
        contract_address: token_address, caller_address: constants::MULTI_SIG_ADDRESS,
    );
    IERC20Dispatcher { contract_address: token_address }
        .approve(spender: manual_strategy_address, amount: Bounded::MAX);

    manual_strategy_address
}

use lbtc_testing::utils::token::init_token_with_roles;
use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::deployment::declare_and_deploy;
use starknet::ContractAddress;
use starkware_utils_testing::{constants as testing_constants, test_utils};

pub mod constants {
    use super::*;

    pub const UPGRADE_DELAY: u64 = 0;
    pub const VAULT: ContractAddress = 'VAULT'.try_into().unwrap();
    pub const NEW_VAULT: ContractAddress = 'NEW_VAULT'.try_into().unwrap();
    pub const ASSET_ROUTER_ADDRESS: ContractAddress = 'ASSET_ROUTER_ADDRESS'.try_into().unwrap();
    pub const FEE: u256 = 5;
}

fn deploy_stake_and_bake(token_address: ContractAddress) -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(testing_constants::GOVERNANCE_ADMIN);
    calldata.append_serde(constants::UPGRADE_DELAY);
    calldata.append_serde(token_address);
    calldata.append_serde(constants::ASSET_ROUTER_ADDRESS);
    calldata.append_serde(constants::VAULT);
    calldata.append_serde(constants::FEE);

    declare_and_deploy("stake_and_bake", calldata)
}

pub fn init_stake_and_bake_with_roles() -> ContractAddress {
    let token_address = init_token_with_roles();
    let stake_and_bake_address = deploy_stake_and_bake(:token_address);
    test_utils::set_default_roles(
        contract: stake_and_bake_address, governance_admin: testing_constants::GOVERNANCE_ADMIN,
    );
    stake_and_bake_address
}

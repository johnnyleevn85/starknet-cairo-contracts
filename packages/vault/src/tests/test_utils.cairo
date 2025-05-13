use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::deployment::declare_and_deploy;
use starknet::ContractAddress;
use starkware_utils_testing::{constants as testing_constants, test_utils};

pub mod constants {
    use super::*;

    pub const UPGRADE_DELAY: u64 = 0;
    pub const TOKEN_ADDRESS: ContractAddress = 'LBTC_TOKEN_ADDRESS'.try_into().unwrap();
    pub const STRATEGY_ADDRESS: ContractAddress = 'MANUAL_STRATEGY_ADDRESS'.try_into().unwrap();
    pub const DEPOSIT_LIMIT: u256 = 1000;
    pub const FEE_RECIPIENT: ContractAddress = 'FEE_RECIPIENT'.try_into().unwrap();
    pub const DEPOSIT_FEE: u128 = 400;
    pub const WITHDRAW_FEE: u128 = 200;
    pub const PROTOCOL_FEE: u128 = 250;
}

fn deploy_vault() -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(testing_constants::GOVERNANCE_ADMIN);
    calldata.append_serde(constants::UPGRADE_DELAY);
    calldata.append_serde(constants::TOKEN_ADDRESS);
    calldata.append_serde(constants::STRATEGY_ADDRESS);
    calldata.append_serde(constants::DEPOSIT_LIMIT);
    calldata.append_serde(constants::FEE_RECIPIENT);
    calldata.append_serde(constants::DEPOSIT_FEE);
    calldata.append_serde(constants::WITHDRAW_FEE);
    calldata.append_serde(constants::PROTOCOL_FEE);

    declare_and_deploy("vault", calldata)
}

pub fn init_vault_with_roles() -> ContractAddress {
    let vault_address = deploy_vault();
    test_utils::set_default_roles(
        contract: vault_address, governance_admin: testing_constants::GOVERNANCE_ADMIN,
    );
    vault_address
}

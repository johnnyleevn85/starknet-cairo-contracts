use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::deployment::declare_and_deploy;
use starknet::ContractAddress;
use starkware_utils_testing::{constants as testing_constants, test_utils};

pub mod constants {
    use super::*;

    pub const UPGRADE_DELAY: u64 = 0;
    pub const TOKEN_ADDRESS: ContractAddress = 'TOKEN_ADDRESS'.try_into().unwrap();
}

fn deploy_manual_strategy() -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(testing_constants::GOVERNANCE_ADMIN);
    calldata.append_serde(constants::UPGRADE_DELAY);
    calldata.append_serde(constants::TOKEN_ADDRESS);

    declare_and_deploy("manual_strategy", calldata)
}

pub fn init_manual_strategy_with_roles() -> ContractAddress {
    let manual_strategy_address = deploy_manual_strategy();
    test_utils::set_default_roles(
        contract: manual_strategy_address, governance_admin: testing_constants::GOVERNANCE_ADMIN,
    );
    manual_strategy_address
}

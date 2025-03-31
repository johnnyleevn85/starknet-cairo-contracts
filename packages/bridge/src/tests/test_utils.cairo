use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::deployment::declare_and_deploy;
use starknet::ContractAddress;
use starkware_utils_testing::constants as testing_constants;

pub mod constants {
    use super::*;

    pub const UPGRADE_DELAY: u64 = 0;
}

pub fn deploy_bridge() -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(testing_constants::GOVERNANCE_ADMIN);
    calldata.append_serde(constants::UPGRADE_DELAY);
    declare_and_deploy("bridge", calldata)
}

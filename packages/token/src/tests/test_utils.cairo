use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::deployment::declare_and_deploy;
use starknet::ContractAddress;
use starkware_utils_testing::{constants as testing_constants, test_utils};

pub mod constants {
    use super::*;

    pub const PERMITTED_MINTER: ContractAddress = 'PERMITTED_MINTER'.try_into().unwrap();
    pub const UPGRADE_DELAY: u64 = 0;
}

fn deploy_lbtc_token() -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(testing_constants::GOVERNANCE_ADMIN);
    calldata.append_serde(array![constants::PERMITTED_MINTER]);
    calldata.append_serde(constants::UPGRADE_DELAY);
    declare_and_deploy("lbtc", calldata)
}

pub fn init_token_with_roles() -> ContractAddress {
    let lbtc_address = deploy_lbtc_token();
    test_utils::set_default_roles(
        contract: lbtc_address, governance_admin: testing_constants::GOVERNANCE_ADMIN,
    );
    lbtc_address
}

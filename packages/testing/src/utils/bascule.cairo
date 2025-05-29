use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::deployment::declare_and_deploy;
use starknet::ContractAddress;
use starkware_utils_testing::{constants as testing_constants, test_utils};

pub mod constants {
    use super::*;

    pub const UPGRADE_DELAY: u64 = 0;
    pub const MAX_DEPOSITS: u32 = 20;
}

fn deploy_bascule() -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(testing_constants::GOVERNANCE_ADMIN);
    calldata.append_serde(constants::UPGRADE_DELAY);
    calldata.append_serde(constants::MAX_DEPOSITS);
    declare_and_deploy("bascule", calldata)
}

pub fn init_bascule_with_roles() -> ContractAddress {
    let bascule_address = deploy_bascule();
    test_utils::set_default_roles(
        contract: bascule_address, governance_admin: testing_constants::GOVERNANCE_ADMIN,
    );
    bascule_address
}

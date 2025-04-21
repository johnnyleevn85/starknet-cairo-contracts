use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::deployment::declare_and_deploy;
use starknet::ContractAddress;
use starkware_utils_testing::{constants as testing_constants, test_utils};

pub mod constants {
    use super::*;

    pub const UPGRADE_DELAY: u64 = 0;
}

fn deploy_vault() -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(testing_constants::GOVERNANCE_ADMIN);
    calldata.append_serde(constants::UPGRADE_DELAY);

    declare_and_deploy("vault", calldata)
}

pub fn init_vault_with_roles() -> ContractAddress {
    let vault_address = deploy_vault();
    test_utils::set_default_roles(
        contract: vault_address, governance_admin: testing_constants::GOVERNANCE_ADMIN,
    );
    vault_address
}

use lbtc_consortium::tests::constants::UPGRADE_DELAY;
use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::deployment::declare_and_deploy;
use starknet::ContractAddress;
use starkware_utils_testing::constants::GOVERNANCE_ADMIN;
use starkware_utils_testing::test_utils::set_default_roles;

fn deploy_contract() -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(GOVERNANCE_ADMIN);
    calldata.append_serde(UPGRADE_DELAY);
    declare_and_deploy("consortium", calldata)
}

pub fn init_contract_with_roles() -> ContractAddress {
    let contract_address = deploy_contract();
    set_default_roles(contract: contract_address, governance_admin: GOVERNANCE_ADMIN);
    contract_address
}

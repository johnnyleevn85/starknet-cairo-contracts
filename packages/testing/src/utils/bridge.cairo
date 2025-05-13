use lbtc_bridge::interface::{IBridgeDispatcher, IBridgeDispatcherTrait};
use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::deployment::declare_and_deploy;
use starknet::ContractAddress;
use starkware_utils_testing::{constants as testing_constants, test_utils};

pub mod constants {
    use super::*;

    pub const UPGRADE_DELAY: u64 = 0;
    pub const LBTC_TOKEN: ContractAddress = 'LBTC_TOKEN'.try_into().unwrap();
    pub const BASCULE: ContractAddress = 'BASCULE'.try_into().unwrap();
    pub const CONSORTIUM: ContractAddress = 'CONSORTIUM'.try_into().unwrap();
    pub const TREASURY: ContractAddress = 'TREASURY'.try_into().unwrap();
    pub const BURN_COMMISSION: u64 = 1;
}

fn deploy_bridge() -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(testing_constants::GOVERNANCE_ADMIN);
    calldata.append_serde(constants::UPGRADE_DELAY);
    calldata.append_serde(constants::BASCULE);
    calldata.append_serde(constants::CONSORTIUM);
    calldata.append_serde(constants::TREASURY);
    calldata.append_serde(constants::BURN_COMMISSION);
    declare_and_deploy("bridge", calldata)
}

pub fn init_bridge_with_roles() -> ContractAddress {
    let bridge_address = deploy_bridge();
    test_utils::set_default_roles(
        contract: bridge_address, governance_admin: testing_constants::GOVERNANCE_ADMIN,
    );
    let bridge = IBridgeDispatcher { contract_address: bridge_address };
    test_utils::cheat_caller_address_once(
        contract_address: bridge_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    bridge.initialize(constants::LBTC_TOKEN);
    bridge_address
}

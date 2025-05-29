use lbtc_bridge::interface::{IBridgeDispatcher, IBridgeDispatcherTrait};
use lbtc_testing::utils::bascule::init_bascule_with_roles;
use lbtc_testing::utils::consortium::init_contract_with_roles as init_consortium_with_roles;
use lbtc_testing::utils::token::init_token_with_roles;
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

fn deploy_bridge(cfg: BridgeInitConfig) -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(cfg.governance_admin);
    calldata.append_serde(cfg.upgrade_delay);
    calldata.append_serde(cfg.bascule);
    calldata.append_serde(cfg.consortium);
    calldata.append_serde(cfg.treasury);
    calldata.append_serde(cfg.burn_commission);
    declare_and_deploy("bridge", calldata)
}

pub fn init_bridge_with_roles() -> ContractAddress {
    let cfg: BridgeInitConfig = Default::default();
    let bridge_address = deploy_bridge(:cfg);
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

pub fn general_contract_system_deployment() -> (
    ContractAddress, ContractAddress, ContractAddress, ContractAddress,
) {
    let token_address = init_token_with_roles();
    let bascule_address = init_bascule_with_roles();
    let consortium_address = init_consortium_with_roles();

    let bridge_init_config = BridgeInitConfig {
        lbtc_token: token_address,
        bascule: bascule_address,
        consortium: consortium_address,
        ..Default::default(),
    };
    let bridge_address = deploy_bridge(cfg: bridge_init_config);
    test_utils::set_default_roles(
        contract: bridge_address, governance_admin: testing_constants::GOVERNANCE_ADMIN,
    );

    let map_selector = selector!("permitted_minters");
    let mut keys = array![];
    bridge_address.serialize(ref keys);
    let storage_address = snforge_std::map_entry_address(:map_selector, keys: keys.span());

    snforge_std::store(
        target: token_address, :storage_address, serialized_value: array![true.into()].span(),
    );

    (token_address, bascule_address, consortium_address, bridge_address)
}

#[derive(Drop, Debug, Copy)]
pub struct BridgeInitConfig {
    governance_admin: ContractAddress,
    upgrade_delay: u64,
    lbtc_token: ContractAddress,
    bascule: ContractAddress,
    consortium: ContractAddress,
    treasury: ContractAddress,
    burn_commission: u64,
}

impl BridgeInitConfigDefault of Default<BridgeInitConfig> {
    fn default() -> BridgeInitConfig {
        BridgeInitConfig {
            governance_admin: testing_constants::GOVERNANCE_ADMIN,
            upgrade_delay: constants::UPGRADE_DELAY,
            lbtc_token: constants::LBTC_TOKEN,
            bascule: constants::BASCULE,
            consortium: constants::CONSORTIUM,
            treasury: constants::TREASURY,
            burn_commission: constants::BURN_COMMISSION,
        }
    }
}

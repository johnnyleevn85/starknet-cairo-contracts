use lbtc_bascule::interface::{IBasculeDispatcher, IBasculeDispatcherTrait};
use lbtc_testing::utils::bascule::init_bascule;
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

fn deploy_asset_router(cfg: AssetRouterInitConfig) -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(cfg.governance_admin);
    calldata.append_serde(cfg.upgrade_delay);
    calldata.append_serde(cfg.bascule);
    calldata.append_serde(cfg.consortium);
    calldata.append_serde(cfg.lbtc_token);
    calldata.append_serde(cfg.treasury);
    calldata.append_serde(cfg.burn_commission);
    declare_and_deploy("asset_router", calldata)
}

pub fn init_asset_router_with_roles() -> ContractAddress {
    let cfg: AssetRouterInitConfig = Default::default();
    let asset_router_address = deploy_asset_router(:cfg);
    test_utils::set_default_roles(
        contract: asset_router_address, governance_admin: testing_constants::GOVERNANCE_ADMIN,
    );

    asset_router_address
}

pub fn general_contract_system_deployment() -> (
    ContractAddress, ContractAddress, ContractAddress, ContractAddress,
) {
    let token_address = init_token_with_roles();
    let bascule_address = init_bascule();
    let consortium_address = init_consortium_with_roles();

    let asset_router_init_config = AssetRouterInitConfig {
        lbtc_token: token_address,
        bascule: bascule_address,
        consortium: consortium_address,
        ..Default::default(),
    };
    let asset_router_address = deploy_asset_router(cfg: asset_router_init_config);
    // Initialize the roles:
    test_utils::set_default_roles(
        contract: asset_router_address, governance_admin: testing_constants::GOVERNANCE_ADMIN,
    );
    test_utils::set_account_as_token_admin(
        contract: token_address,
        account: asset_router_address,
        app_role_admin: testing_constants::APP_ROLE_ADMIN,
    );

    let bascule_dispatcher = IBasculeDispatcher { contract_address: bascule_address };
    test_utils::cheat_caller_address_once(
        contract_address: bascule_address, caller_address: testing_constants::GOVERNANCE_ADMIN,
    );
    bascule_dispatcher.register_withdrawal_validator(account: asset_router_address);

    (token_address, bascule_address, consortium_address, asset_router_address)
}

#[derive(Drop, Debug, Copy)]
pub struct AssetRouterInitConfig {
    governance_admin: ContractAddress,
    upgrade_delay: u64,
    lbtc_token: ContractAddress,
    bascule: ContractAddress,
    consortium: ContractAddress,
    treasury: ContractAddress,
    burn_commission: u64,
}

impl AssetRouterInitConfigDefault of Default<AssetRouterInitConfig> {
    fn default() -> AssetRouterInitConfig {
        AssetRouterInitConfig {
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

pub fn cheat_caller_for_mint(asset_router_address: ContractAddress) {
    snforge_std::cheat_chain_id(
        contract_address: asset_router_address,
        chain_id: 1,
        span: snforge_std::CheatSpan::TargetCalls(1),
    );
}

pub fn cheat_caller_for_redeem(
    asset_router_address: ContractAddress,
    lbtc_address: ContractAddress,
    recipient: ContractAddress,
) {
    test_utils::cheat_caller_address_once(
        contract_address: asset_router_address, caller_address: recipient,
    );
    // For permissioned mint, and permissioned burn.
    snforge_std::cheat_caller_address(
        contract_address: lbtc_address,
        caller_address: testing_constants::TOKEN_ADMIN,
        span: snforge_std::CheatSpan::TargetCalls(2),
    );
}

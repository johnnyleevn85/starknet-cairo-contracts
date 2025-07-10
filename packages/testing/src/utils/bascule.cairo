use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::deployment::declare_and_deploy;
use starknet::ContractAddress;
use starkware_utils_testing::constants as testing_constants;

pub mod constants {
    use super::*;

    pub const MAX_DEPOSITS: u32 = 20;

    // These fields are taken from this tx:
    // https://etherscan.io/tx/0x49f935f83533f509510c0cd387a44d67342a89e3f9048a6327d5a3e36695a005.
    // The deposit_id is computed from the payload.
    pub const TO_CHAIN: u256 = 0x1;
    pub const RECIPIENT: ContractAddress = 0xbe6afb3a18bbb8f35e2a12c330d0e37daebab802
        .try_into()
        .unwrap();
    pub const WITHDRAWAL_AMOUNT: u256 = 0xb061cf0;
    pub const TX_ID: u256 = 0x8b881e06005aff8dd8768600d785d9d0027b65896368dbf3bd6fbf13ae8fb9d1_u256;
    pub const VOUT: u32 = 0x0;

    // The deposit_id is computed using an online keccak calculator (Hex input encoding).
    // The payload was taken from etherscan, notice that removing the selector
    // DEPOSIT_BTC_ACTION from the beginning of the payload was needed to get the correct id.
    pub const DEPOSIT_ID: u256 =
        0xd0196c21127ebd186b28e7d84dddbfa51c82b1667757350581259d9b1a03d9b5_u256;

    pub const PAUSER: ContractAddress = 'PAUSER'.try_into().unwrap();
    pub const DEPOSIT_REPORTER: ContractAddress = 'DEPOSIT_REPORTER'.try_into().unwrap();
    pub const WITHDRAWAL_VALIDATOR: ContractAddress = 'WITHDRAWAL_VALIDATOR'.try_into().unwrap();
}

fn deploy_bascule(cfg: BasculeInitConfig) -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(cfg.governance_admin);
    calldata.append_serde(cfg.pauser);
    calldata.append_serde(cfg.deposit_reporter);
    calldata.append_serde(cfg.withdrawal_validator);
    calldata.append_serde(cfg.max_deposits);
    declare_and_deploy("bascule", calldata)
}

pub fn init_bascule() -> ContractAddress {
    let cfg: BasculeInitConfig = Default::default();
    let bascule_address = deploy_bascule(:cfg);
    bascule_address
}

#[derive(Drop, Debug, Copy)]
pub struct BasculeInitConfig {
    governance_admin: ContractAddress,
    pauser: ContractAddress,
    deposit_reporter: ContractAddress,
    withdrawal_validator: ContractAddress,
    max_deposits: u32,
}

impl BasculeInitConfigDefault of Default<BasculeInitConfig> {
    fn default() -> BasculeInitConfig {
        BasculeInitConfig {
            governance_admin: testing_constants::GOVERNANCE_ADMIN,
            pauser: constants::PAUSER,
            deposit_reporter: constants::DEPOSIT_REPORTER,
            withdrawal_validator: constants::WITHDRAWAL_VALIDATOR,
            max_deposits: constants::MAX_DEPOSITS,
        }
    }
}

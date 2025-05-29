use sncast_std::{declare, deploy, DeclareResultTrait, get_nonce, FeeSettingsTrait};
use openzeppelin::utils::serde::SerializedAppend;
use starknet::ContractAddress;

// Some example:
// https://foundry-rs.github.io/starknet-foundry/starknet/script.html#full-example-with-contract-deployment

pub const MULTISIG_ACCOUNT: ContractAddress = 0x001aFebfe9bd3cA1E3315E1B53D92040230c2361AE6848c3046A4eB13C5bfF26.try_into().unwrap();
pub const TREASURY_1: ContractAddress = 0x009D9aA1ef7e08519bB9DdeE4E749cFf4F9f8B8F46143C2071E3DAbf3B3Dcf8c.try_into().unwrap();
pub const TREASURY_2: ContractAddress = 0x02551b1f37dAD720a72ABeFc954428a045715817d21642dc12DD92605dA9E63a.try_into().unwrap();

// pub const GOVERNANCE_ADMIN: ContractAddress = 0x18fb2fcd0f285174a0aa6dc2f8b6bd3b5020ead1f90ed29e45a0e5d874121a9.try_into().unwrap();
pub const GOVERNANCE_ADMIN: ContractAddress = MULTISIG_ACCOUNT;
pub const PERMITTED_MINTER: ContractAddress = 0x18fb2fcd0f285174a0aa6dc2f8b6bd3b5020ead1f90ed29e45a0e5d874121a9.try_into().unwrap();
pub const UPGRADE_DELAY: u64 = 0;
pub const BURN_COMMISSION: u64 = 1000;

fn deploy_contract(name: ByteArray, calldata: Array<felt252>, unique: bool) -> ContractAddress {
    let mut name1 = name.clone();
    println!("Deploying {name1}");

    let fee_settings = FeeSettingsTrait::estimate();
    let declare_nonce = get_nonce('pending');

    name1 = name.clone();
    let declare_result = declare(name1, fee_settings, Option::Some(declare_nonce))
        .expect('contract declare failed');
    // match self {
    //     Ok(x) => x,
    //     Err(_) => crate::panic_with_felt252(err),
    // }
    let class_hash = declare_result.class_hash();
    let class_hash_felt252: felt252 = (*class_hash).into();
    name1 = name.clone();
    println!("Declared {name1} successfully, class_hash: {:x}", class_hash_felt252);

    let deploy_nonce = get_nonce('pending');

    let deploy_result = deploy(
        *class_hash,
        calldata,
        None,
        unique,
        fee_settings,
        Option::Some(deploy_nonce),
    )
        .expect('contract deploy failed');

    assert(deploy_result.transaction_hash != 0, deploy_result.transaction_hash);

    let contract_address_felt252: felt252 = deploy_result.contract_address.into();
    name1 = name.clone();
    println!("Deployed {} successfully, contract address: {:x}", name1, contract_address_felt252);
    return  deploy_result.contract_address;
}

fn main() {
    println!("Deploy contracts: START");

    // let salt = 0x3;

    // Deploy lbtc
    let mut bridge_calldata = array![];
    bridge_calldata.append_serde(GOVERNANCE_ADMIN); // Governance admin
    bridge_calldata.append_serde(UPGRADE_DELAY); // Upgrade delay
    bridge_calldata.append_serde(GOVERNANCE_ADMIN); // Bascule
    bridge_calldata.append_serde(GOVERNANCE_ADMIN); // Consortium
    bridge_calldata.append_serde(TREASURY_1); // Treasury
    bridge_calldata.append_serde(BURN_COMMISSION); // Burn commission
    let bridge_address = deploy_contract("bridge", bridge_calldata, true);

    // Deploy lbtc
    let mut lbtc_calldata = array![];
    lbtc_calldata.append_serde(GOVERNANCE_ADMIN); // Governance admin
    lbtc_calldata.append_serde(array![bridge_address]); // Pemitted minters
    lbtc_calldata.append_serde(UPGRADE_DELAY); // Upgrade delay
    let _lbtc_address = deploy_contract("lbtc", lbtc_calldata, true);

    // // Change treasury
    // let invoke_nonce = get_nonce('pending');
    // let mut invoke_calldata = array![];
    // invoke_calldata.append_serde(TREASURY_2); // New treasury
    // let invoke_result = invoke(bridge_address, selector!("change_treasury"), invoke_calldata, fee_settings, Option::Some(invoke_nonce),)
    //     .expect('map invoke failed');
    // assert(invoke_result.transaction_hash != 0, invoke_result.transaction_hash);


    println!("Deploy contracts: DONE");
}

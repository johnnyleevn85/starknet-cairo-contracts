use sncast_std::{declare, deploy, DeclareResultTrait, get_nonce, FeeSettingsTrait};
use openzeppelin::utils::serde::SerializedAppend;
use starknet::ContractAddress;

// Some example:
// https://foundry-rs.github.io/starknet-foundry/starknet/script.html#full-example-with-contract-deployment

pub const GOVERNANCE_ADMIN: ContractAddress = 0x18fb2fcd0f285174a0aa6dc2f8b6bd3b5020ead1f90ed29e45a0e5d874121a9.try_into().unwrap();
pub const PERMITTED_MINTER: ContractAddress = 0x18fb2fcd0f285174a0aa6dc2f8b6bd3b5020ead1f90ed29e45a0e5d874121a9.try_into().unwrap();
pub const UPGRADE_DELAY: u64 = 0;

fn main() {
    println!("Deploy contracts: START");

    println!("Deploying lbtc");

    let fee_settings = FeeSettingsTrait::estimate();
    // let salt = 0x3;

    let declare_nonce = get_nonce('latest');

    let declare_result = declare("lbtc", fee_settings, Option::Some(declare_nonce))
        .expect('lbtc declare failed');

    let class_hash = declare_result.class_hash();
    let class_hash_felt252: felt252 = (*class_hash).into();
    println!("Declared lbtc successfully, class_hash: {:x}", class_hash_felt252);

    let deploy_nonce = get_nonce('pending');

    let mut calldata = array![];
    calldata.append_serde(GOVERNANCE_ADMIN);
    calldata.append_serde(array![PERMITTED_MINTER]);
    calldata.append_serde(UPGRADE_DELAY);

    let deploy_result = deploy(
        *class_hash,
        calldata,
        None,
        true,
        fee_settings,
        Option::Some(deploy_nonce),
    )
        .expect('lbtc deploy failed');

    assert(deploy_result.transaction_hash != 0, deploy_result.transaction_hash);

    let contract_address_felt252: felt252 = deploy_result.contract_address.into();
    println!("Deployed lbtc successfully, contract address: {:x}", contract_address_felt252);

    println!("Deploy contracts: DONE");
}

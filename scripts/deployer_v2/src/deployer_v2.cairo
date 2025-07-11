use starknet::ClassHash;
// use sncast_std::invoke;
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
pub const MAX_DEPOSITS: u64 = 100;
pub const BURN_COMMISSION: u64 = 1000;

pub const BASCULE_CLASSS_HASH: felt252 = 0x83965992f591e5979068d8a12a09a1f13949e1d1f65f495e7a5503d2f1e519;
pub const CONSORTIUM_CLASSS_HASH: felt252 = 0xa6410783177211d658ad025479b4392bb1076d9387b9fab630c9432550d445;
pub const LBTC_CLASSS_HASH: felt252 = 0x7825833d4a2c39c770284dc4d9ae7235d2129a0e9c06f6c3d945b31633c135d;
pub const BRIDGE_CLASSS_HASH: felt252 = 0x45dbeac301d4d2ee1668f0046c3cd14b2ce0c9a82449ede1ee60b6f42c9d4e1;

fn deploy_contract(name: ByteArray, calldata: Array<felt252>, unique: bool, known_class_hash: Option<felt252>) -> ContractAddress {
    let mut name1 = name.clone();
    println!("Deploying {name1}");

    let fee_settings = FeeSettingsTrait::estimate();
    let declare_nonce = get_nonce('pending');

    name1 = name.clone();
    let zero_hash: felt252 = 0.try_into().unwrap();
    let mut class_hash: ClassHash = zero_hash.try_into().unwrap();
    if known_class_hash.is_some() {
        class_hash = known_class_hash.unwrap().try_into().unwrap();
    } else {
        let declare_result = declare(name1, fee_settings, Option::Some(declare_nonce))
            .expect('contract declare failed');
        // match self {
        //     Ok(x) => x,
        //     Err(_) => crate::panic_with_felt252(err),
        // }
        class_hash = *declare_result.class_hash();
    }
    let class_hash_felt252: felt252 = (class_hash).into();
    name1 = name.clone();
    println!("Declared {name1} successfully, class_hash: {:x}", class_hash_felt252);

    let deploy_nonce = get_nonce('pending');

    let deploy_result = deploy(
        class_hash,
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

    // Deploy bascule
    let mut bascule_calldata = array![];
    bascule_calldata.append_serde(GOVERNANCE_ADMIN); // Governance admin
    bascule_calldata.append_serde(GOVERNANCE_ADMIN); // Pauser
    bascule_calldata.append_serde(GOVERNANCE_ADMIN); // Reporter
    bascule_calldata.append_serde(GOVERNANCE_ADMIN); // Withdrawal validator
    bascule_calldata.append_serde(MAX_DEPOSITS); // Max deposits
    let bascule_address = deploy_contract("bascule", bascule_calldata, true, Some(BASCULE_CLASSS_HASH));
    // let bascule_address = deploy_contract("bascule", bascule_calldata, false, Some(BASCULE_CLASSS_HASH));

    // Deploy consortium
    let mut consortium_calldata = array![];
    consortium_calldata.append_serde(GOVERNANCE_ADMIN); // Governance admin
    consortium_calldata.append_serde(UPGRADE_DELAY); // Upgrade delay
    let consortium_address = deploy_contract("consortium", consortium_calldata, true, Some(CONSORTIUM_CLASSS_HASH));

    // Deploy lbtc
    let mut lbtc_calldata = array![];
    lbtc_calldata.append_serde(GOVERNANCE_ADMIN); // Governance admin
    lbtc_calldata.append_serde(UPGRADE_DELAY); // Upgrade delay
    let _lbtc_address = deploy_contract("lbtc", lbtc_calldata, true, Some(LBTC_CLASSS_HASH));

    // Deploy bridge
    let mut bridge_calldata = array![];
    bridge_calldata.append_serde(GOVERNANCE_ADMIN); // Governance admin
    bridge_calldata.append_serde(UPGRADE_DELAY); // Upgrade delay
    bridge_calldata.append_serde(bascule_address); // Bascule
    bridge_calldata.append_serde(consortium_address); // Consortium
    bridge_calldata.append_serde(TREASURY_1); // Treasury
    bridge_calldata.append_serde(BURN_COMMISSION); // Burn commission
    let _bridge_address = deploy_contract("bridge", bridge_calldata, true, Some(BRIDGE_CLASSS_HASH));

    // // Set LBTC token on the bridge - but this should be done by governance admin (multisig)
    let invoke_nonce = get_nonce('pending');
    let mut invoke_calldata = array![];
    invoke_calldata.append_serde(lbtc_address); // New treasury
    let invoke_result = invoke(bridge_address, selector!("initialize"), invoke_calldata, FeeSettingsTrait::estimate(), Option::Some(invoke_nonce),)
        .expect('map invoke failed');
    assert(invoke_result.transaction_hash != 0, invoke_result.transaction_hash);

    // ToDO:
    // 0. bascule: add app admin role to governance admin
    // 1. bascule: set bridge as token admin
    // 2. bascule: set deposit reporter as token operator
    // 3. consortium: set ValSet
    // 4. lbtc: add app admin role to governance admin
    // 5. lbtc: set bridge as permitted minter -> token admin role
    // 6. bridge: set lbtc address

    println!("Deploy contracts: DONE");
}

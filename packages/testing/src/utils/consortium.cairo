use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::deployment::declare_and_deploy;
use openzeppelin_testing::signing::{Secp256k1KeyPair, get_secp256k1_keys_from};
use starknet::secp256_trait::{Secp256PointTrait, Secp256Trait};
use starknet::secp256k1::Secp256k1Point;
use starknet::{ContractAddress, SyscallResultTrait};
use starkware_utils_testing::constants::GOVERNANCE_ADMIN;
use starkware_utils_testing::test_utils::set_default_roles;

pub mod constants {
    pub const UPGRADE_DELAY: u64 = 1;
}

fn deploy_contract() -> ContractAddress {
    let mut calldata = array![];
    calldata.append_serde(GOVERNANCE_ADMIN);
    calldata.append_serde(constants::UPGRADE_DELAY);
    declare_and_deploy("consortium", calldata)
}

pub fn init_contract_with_roles() -> ContractAddress {
    let contract_address = deploy_contract();
    set_default_roles(contract: contract_address, governance_admin: GOVERNANCE_ADMIN);
    contract_address
}

pub fn generate_public_key(secret_key: u256) -> ((u256, u256), Secp256k1KeyPair) {
    let key_pair = get_secp256k1_keys_from(secret_key);
    let generator = Secp256Trait::<Secp256k1Point>::get_generator_point();
    let public_key = Secp256PointTrait::mul(generator, secret_key)
        .unwrap_syscall()
        .get_coordinates()
        .unwrap();

    (public_key, key_pair)
}

use starknet::ContractAddress;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct AssetsForwareded {
    pub asset_address: ContractAddress,
    pub assets: u256,
    pub multi_sig: ContractAddress,
}

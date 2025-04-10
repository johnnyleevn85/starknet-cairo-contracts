use starknet::ContractAddress;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct MinterAdded {
    pub minter: ContractAddress,
}

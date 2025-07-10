use starknet::ContractAddress;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct FeeChanged {
    pub old_fee: u256,
    pub new_fee: u256,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct DepositorSet {
    #[key]
    pub depositor: ContractAddress,
}

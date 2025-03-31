use starknet::ContractAddress;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct ConsortiumChanged {
    pub old_consortium: ContractAddress,
    pub new_consortium: ContractAddress,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct TreasuryChanged {
    pub old_treasury: ContractAddress,
    pub new_treasury: ContractAddress,
}

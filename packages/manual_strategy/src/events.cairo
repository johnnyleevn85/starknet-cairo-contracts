use starknet::ContractAddress;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct AssetsForwarded {
    pub asset_address: ContractAddress,
    pub assets: u256,
    pub multi_sig: ContractAddress,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct AmountUpdated {
    pub amount: u256,
    pub is_withdrawal: bool,
    pub old_deposited_amount: u256,
    pub new_deposited_amount: u256,
}

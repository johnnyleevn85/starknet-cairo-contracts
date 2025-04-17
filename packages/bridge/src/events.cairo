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

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct BurnCommissionChanged {
    pub old_burn_commission: u64,
    pub new_burn_commission: u64,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct BasculeChanged {
    pub old_bascule: ContractAddress,
    pub new_bascule: ContractAddress,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct WithdrawalsEnabled {
    pub is_withdrawals_enabled: bool,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct DustFeeRateChanged {
    pub old_rate: u128,
    pub new_rate: u128,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct UpdateValidateThreshold {
    pub old_threshold: u128,
    pub new_threshold: u128,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct MaxDepositsUpdated {
    pub num_deposits: u16,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct DepositsReported {
    #[key]
    pub report_id: felt252,
    pub num_deposits: u32,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct DepositAlreadyReported {
    #[key]
    pub deposit_id: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct WithdrawalNotValidated {
    #[key]
    pub deposit_id: felt252,
    pub withdrawal_amount: u128,
}


#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct WithdrawalValidated {
    #[key]
    pub deposit_id: felt252,
    pub withdrawal_amount: u128,
}

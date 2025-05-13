use starknet::ContractAddress;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct DepositLimitSet {
    pub limit: u256,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct FeeRecipientUpdated {
    #[key]
    pub old_recipient: ContractAddress,
    #[key]
    pub new_recipient: ContractAddress,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct WithdrawalPausedToggled {
    pub past_value: bool,
    pub new_value: bool,
}

use starknet::ContractAddress;

#[starknet::interface]
pub trait IBascule<TContractState> {
    /// Validates a withdrawal (before executing it) if the amount is above a threshold.
    ///
    /// This function checks whether our internal accounting has recorded a deposit that
    /// corresponds to the provided withdrawal request. Each deposit can be withdrawn only once.
    ///
    /// # Parameters
    /// - `deposit_id`: A unique identifier of the deposit on another chain.
    /// - `withdrawal_amount`: The amount requested for withdrawal.
    ///
    /// Emits a `WithdrawalValidated` event if the validation passes.
    ///
    /// Based on:
    /// <https://github.com/lombard-finance/evm-smart-contracts/blob/main/contracts/bascule/interfaces/IBascule.sol>
    fn validate_withdrawal(
        ref self: TContractState,
        to_chain: u256,
        recipient: ContractAddress,
        withdrawal_amount: u256,
        tx_id: u256,
        vout: u32,
    );

    fn update_validation_threshold(ref self: TContractState, new_threshold: u256);
    fn set_max_deposits(ref self: TContractState, max_deposits: u32);
    fn report_deposits(ref self: TContractState, report_id: u256, deposit_ids: Span<u256>);

    /// View functions
    fn get_validation_threshold(self: @TContractState) -> u256;
    fn get_max_deposits(self: @TContractState) -> u32;
    fn get_deposit_status(self: @TContractState, deposit_id: u256) -> DepositState;

    /// Role functions

    /// Deposit Reporter Role
    fn is_deposit_reporter(self: @TContractState, account: ContractAddress) -> bool;
    fn register_deposit_reporter(ref self: TContractState, account: ContractAddress);
    fn remove_deposit_reporter(ref self: TContractState, account: ContractAddress);

    /// Withdrawal Validator Role
    fn is_withdrawal_validator(self: @TContractState, account: ContractAddress) -> bool;
    fn register_withdrawal_validator(ref self: TContractState, account: ContractAddress);
    fn remove_withdrawal_validator(ref self: TContractState, account: ContractAddress);

    /// Validation Guardian Role
    fn is_validation_guardian(self: @TContractState, account: ContractAddress) -> bool;
    fn register_validation_guardian(ref self: TContractState, account: ContractAddress);
    fn remove_validation_guardian(ref self: TContractState, account: ContractAddress);

    /// Pauser Role
    fn is_pauser(self: @TContractState, account: ContractAddress) -> bool;
    fn register_pauser(ref self: TContractState, account: ContractAddress);
    fn remove_pauser(ref self: TContractState, account: ContractAddress);
}


#[derive(Copy, Debug, Drop, PartialEq, Serde, starknet::Store)]
pub enum DepositState {
    #[default]
    Unreported,
    Reported,
    Withdrawn,
}

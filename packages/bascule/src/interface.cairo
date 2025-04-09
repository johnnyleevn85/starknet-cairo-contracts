use lbtc_bascule::types::DepositState;
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
    fn validate_withdrawal(ref self: TContractState, deposit_id: u256, withdrawal_amount: u128);

    fn update_validation_threshold(ref self: TContractState, new_threshold: u128);
    fn set_max_deposits(ref self: TContractState, max_deposits: u32);
    fn report_deposits(ref self: TContractState, report_id: u256, deposit_ids: Array<u256>);

    /// View functions
    fn get_validatation_threshold(self: @TContractState) -> u128;
    fn get_max_deposits(self: @TContractState) -> u32;
    fn get_validation_consumer(self: @TContractState) -> ContractAddress;
    fn get_deposit_status(self: @TContractState, deposit_id: u256) -> DepositState;
}

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
    fn validate_withdrawal(ref self: TContractState, deposit_id: felt252, withdrawal_amount: u128);
}

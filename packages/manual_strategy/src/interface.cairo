use starknet::ContractAddress;

#[starknet::interface]
pub trait IManualStrategy<TContractState> {
    /// Enables the withdrawals from the strategy.
    fn enable_withdraw(ref self: TContractState);
    /// Disables the withdrawals from the strategy.
    fn disable_withdraw(ref self: TContractState);
    /// Updates the amount of assets deposited into the strategy.
    /// The flag `is_deposit` indicates if the amount is a deposit or a withdrawal.
    // TODO(Gil): Consider wrapping this function in two functions, one for deposit and one for
    // withdrawal.
    fn update_amount(ref self: TContractState, amount: u256, is_withdrawal: bool);
    /// Returns the amount of assets available for withdrawal from the strategy.
    fn get_available_assets_for_withdrawal(self: @TContractState) -> u256;
    /// Sets the multi-sig address for the strategy.
    fn set_multi_sig(ref self: TContractState, multi_sig_address: ContractAddress);
    /// Returns the multi-sig address for the strategy.
    fn get_multi_sig(self: @TContractState) -> ContractAddress;
    /// Returns the amount of assets managed by the strategy.
    fn get_amount(self: @TContractState) -> u256;
    // Checks if withdraw is enabled.
    fn is_withdraw_enabled(self: @TContractState) -> bool;
    // Sets the deposit limit.
    fn set_deposit_limit(ref self: TContractState, new_limit: u256);
    // Returns the deposit limit.
    fn get_deposit_limit(self: @TContractState) -> u256;
}


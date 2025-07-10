use starknet::ContractAddress;

#[starknet::interface]
pub trait IVault<TContractState> {
    fn enable_withdrawals(ref self: TContractState);
    fn disable_withdrawals(ref self: TContractState);

    fn set_fee_recipient(ref self: TContractState, new_recipient: ContractAddress);
    fn set_deposit_limit(ref self: TContractState, new_limit: u256);
    fn set_fees(
        ref self: TContractState,
        deposit_fee: u64,
        withdrawal_fee: u64,
        protocol_fee: u64,
        performance_fee: Span<(u256, u256, u64)>,
    );

    fn force_pause(ref self: TContractState);

    // View functions.
    fn get_fee_recipient(self: @TContractState) -> ContractAddress;
    fn get_deposit_fee(self: @TContractState) -> u64;
    fn get_withdrawal_fee(self: @TContractState) -> u64;
    fn get_protocol_fee(self: @TContractState) -> u64;
    fn get_deposit_limit(self: @TContractState) -> u256;
    fn get_available_assets_for_withdrawal(self: @TContractState) -> u256;
    fn accrued_protocol_fee(self: @TContractState) -> u256;
    fn accrued_performance_fee(self: @TContractState) -> u256;
}


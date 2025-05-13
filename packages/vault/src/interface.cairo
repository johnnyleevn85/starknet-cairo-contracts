use starknet::ContractAddress;

#[starknet::interface]
pub trait IVault<TContractState> {
    fn deposit(ref self: TContractState, assets: u256, receiver: ContractAddress) -> u256;
    fn mint(ref self: TContractState, shares: u128, receiver: ContractAddress) -> u128;
    fn withdraw(
        ref self: TContractState, assets: u128, receiver: ContractAddress, owner: ContractAddress,
    ) -> u128;
    fn redeem(
        ref self: TContractState, shares: u128, receiver: ContractAddress, owner: ContractAddress,
    ) -> u128;

    fn preview_deposit(self: @TContractState, assets: u256) -> u256;
    fn preview_mint(self: @TContractState, shares: u256) -> u256;
    fn preview_withdraw(self: @TContractState, assets: u256) -> u256;
    fn preview_redeem(self: @TContractState, shares: u256) -> u256;

    fn enable_withdrawals(ref self: TContractState);
    fn disable_withdrawals(ref self: TContractState);

    fn set_fee_recipient(ref self: TContractState, new_recipient: ContractAddress);
    fn set_deposit_limit(ref self: TContractState, new_limit: u256);
    fn set_fees(ref self: TContractState, deposit_fee: u64, withdrawal_fee: u64, protocol_fee: u64);

    // View functions.
    fn max_mint(self: @TContractState) -> u128;
    fn max_withdraw(self: @TContractState, owner: ContractAddress) -> u256;
    fn get_fee_recipient(self: @TContractState) -> ContractAddress;
    fn get_deposit_fee(self: @TContractState) -> u64;
    fn get_withdrawal_fee(self: @TContractState) -> u64;
    fn get_protocol_fee(self: @TContractState) -> u64;
    fn get_deposit_limit(self: @TContractState) -> u256;
    fn get_total_assets(self: @TContractState) -> u256;
    fn get_total_supply(self: @TContractState) -> u256;
    fn get_available_assets_for_withdrawal(self: @TContractState) -> u128;
    fn accrued_protocol_fee(self: @TContractState) -> u256;
}


use starknet::ContractAddress;

#[starknet::interface]
pub trait IBridge<TContractState> {
    fn change_consortium(ref self: TContractState, new_consortium: ContractAddress);
    fn get_consortium(self: @TContractState) -> ContractAddress;
    fn change_treasury(ref self: TContractState, new_treasury: ContractAddress);
    fn get_treasury(self: @TContractState) -> ContractAddress;
}

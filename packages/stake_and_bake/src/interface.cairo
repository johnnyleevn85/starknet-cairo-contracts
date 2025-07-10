use lbtc_consortium::interface::Signature;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IStakeAndBake<TContractState> {
    fn batch_stake_and_bake(
        ref self: TContractState,
        to_chain: Span<u256>,
        recipient: Span<ContractAddress>,
        amount: Span<u256>,
        tx_id: Span<u256>,
        vout: Span<u32>,
        proof: Span<Span<Signature>>,
        deadline: Span<u64>,
        signature: Span<Span<felt252>>,
        min_mint: Span<u256>,
    );
    fn stake_and_bake(
        ref self: TContractState,
        to_chain: u256,
        recipient: ContractAddress,
        amount: u256,
        tx_id: u256,
        vout: u32,
        proof: Span<Signature>,
        deadline: u64,
        signature: Span<felt252>,
        min_mint: u256,
    );
    fn set_depositor(ref self: TContractState, vault: ContractAddress);
    fn set_fee(ref self: TContractState, fee: u256);

    fn get_stake_and_bake_depositor(self: @TContractState) -> ContractAddress;
    fn get_stake_and_bake_fee(self: @TContractState) -> u256;
}


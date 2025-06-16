use lbtc_consortium::interface::Signature;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IStakeAndBake<TContractState> {
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
    );
    fn set_fee(ref self: TContractState, fee: u256);

    fn get_vault(self: @TContractState) -> ContractAddress;
    fn get_stake_and_bake_fee(self: @TContractState) -> u256;
}


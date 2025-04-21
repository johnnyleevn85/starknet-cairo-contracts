#[starknet::interface]
pub trait IVault<TContractState> {
    fn foo(ref self: TContractState) -> u128;
}


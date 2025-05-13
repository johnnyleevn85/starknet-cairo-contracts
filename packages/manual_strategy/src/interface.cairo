#[starknet::interface]
pub trait IManualStrategy<TContractState> {
    fn foo(ref self: TContractState) -> u128;
}


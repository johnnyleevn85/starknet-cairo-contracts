#[starknet::contract]
mod consortium {
    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
    ) {}
}

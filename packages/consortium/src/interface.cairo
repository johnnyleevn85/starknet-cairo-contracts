use starknet::eth_address::EthAddress;

pub type PublicKey = (u256, u256);
pub type Signature = (u256, u256);

#[starknet::interface]
pub trait IConsortium<TContractState> {
    fn set_initial_validator_set(
        ref self: TContractState,
        public_keys: Span<PublicKey>,
        weights: Span<u128>,
        threshold_weight: u128,
    );
    fn set_next_validator_set(
        ref self: TContractState,
        epoch: u64,
        public_keys: Span<PublicKey>,
        weights: Span<u128>,
        threshold_weight: u128,
        height: u128,
        proof: Span<Signature>,
    );
    fn check_proof(self: @TContractState, msg_hash: u256, proof: Span<Signature>);
    fn get_validator_set(self: @TContractState, epoch: u64) -> (Span<EthAddress>, Span<u128>, u128);
    fn get_current_epoch(self: @TContractState) -> u64;
}

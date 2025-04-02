use starknet::eth_address::EthAddress;
use starkware_utils::types::Signature;

#[starknet::interface]
pub trait IConsortium<TContractState> {
    fn set_initial_validator_set(
        ref self: TContractState,
        validators: Array<EthAddress>,
        weights: Array<u128>,
        threshold_weight: u128,
    );
    fn set_next_validator_set(
        ref self: TContractState,
        validators: Array<EthAddress>,
        weights: Array<u128>,
        threshold_weight: u128,
        proof: Array<Signature>,
    );
    fn check_proof(self: @TContractState, payload_hash: felt252, proof: Array<Signature>);
    fn get_validator_set(
        self: @TContractState, epoch: u64,
    ) -> (Array<EthAddress>, Array<u128>, u128);
    fn get_current_epoch(self: @TContractState) -> u64;
}

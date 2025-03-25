use starkware_utils::types::Signature;

#[starknet::interface]
pub trait IConsortium<TContractState> {
    fn set_initial_validator_set(
        ref self: TContractState,
        validator_pks: Array<felt252>,
        weights: Array<u128>,
        weight_threshold: u128,
    );
    fn set_next_validator_set(
        ref self: TContractState,
        validator_pks: Array<felt252>,
        weights: Array<u128>,
        weight_threshold: u128,
        proof: Array<Signature>,
        signer_pks: Array<felt252>,
    );
    fn check_proof(
        self: @TContractState,
        payload_hash: felt252,
        proof: Array<Signature>,
        signer_pks: Array<felt252>,
    );
    fn get_validator_set(self: @TContractState, epoch: u64) -> (Array<felt252>, Array<u128>, u128);
    fn get_current_epoch(self: @TContractState) -> u64;
}

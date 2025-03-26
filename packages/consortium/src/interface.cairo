use starkware_utils::types::{PublicKey, Signature};

#[starknet::interface]
pub trait IConsortium<TContractState> {
    fn set_initial_validator_set(
        ref self: TContractState,
        validator_pks: Array<PublicKey>,
        weights: Array<u128>,
        weight_threshold: u128,
    );
    fn set_next_validator_set(
        ref self: TContractState,
        validator_pks: Array<PublicKey>,
        weights: Array<u128>,
        weight_threshold: u128,
        proof: Array<Signature>,
        signer_pks: Array<PublicKey>,
    );
    fn check_proof(
        self: @TContractState,
        payload_hash: felt252,
        proof: Array<Signature>,
        signer_pks: Array<PublicKey>,
    );
    fn get_validator_set(
        self: @TContractState, epoch: u64,
    ) -> (Array<PublicKey>, Array<u128>, u128);
    fn get_current_epoch(self: @TContractState) -> u64;
}

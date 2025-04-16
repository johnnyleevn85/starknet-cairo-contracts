use starknet::eth_address::EthAddress;

pub type PublicKey = (u256, u256);
pub type Signature = (u256, u256);

#[starknet::interface]
pub trait IConsortium<TContractState> {
    fn set_initial_validator_set(
        ref self: TContractState,
        validators: Array<PublicKey>,
        weights: Array<u128>,
        threshold_weight: u128,
    );
    fn set_next_validator_set(
        ref self: TContractState,
        epoch: u64,
        validators: Array<PublicKey>,
        weights: Array<u128>,
        threshold_weight: u128,
        height: u128,
        proof: Array<Signature>,
    );
    fn check_proof(self: @TContractState, msg_hash: u256, proof: Array<Signature>);
    fn get_validator_set(
        self: @TContractState, epoch: u64,
    ) -> (Array<EthAddress>, Array<u128>, u128);
    fn get_current_epoch(self: @TContractState) -> u64;
}

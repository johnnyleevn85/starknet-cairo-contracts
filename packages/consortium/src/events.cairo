use starkware_utils::types::PublicKey;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct ValidatorSetUpdated {
    #[key]
    pub epoch: u64,
    pub validators: Array<PublicKey>,
    pub weights: Array<u128>,
    pub threshold: u128,
}

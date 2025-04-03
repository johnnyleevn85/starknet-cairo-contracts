use starknet::eth_address::EthAddress;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct ValidatorSetUpdated {
    #[key]
    pub epoch: u64,
    pub validators: Array<EthAddress>,
    pub weights: Array<u128>,
    pub threshold: u128,
}

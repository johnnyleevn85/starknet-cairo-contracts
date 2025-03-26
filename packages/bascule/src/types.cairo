#[derive(Copy, Debug, Drop, PartialEq, Serde, starknet::Store)]
pub enum DepositState {
    #[default]
    UNREPORTED,
    REPORTED,
    WITHDRAWN,
}

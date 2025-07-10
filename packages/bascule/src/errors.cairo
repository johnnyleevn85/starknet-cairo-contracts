pub const BAD_DEPOSIT_REPORT: felt252 = 'BAD_DEPOSIT_REPORT';
pub const INVALID_DEPOSIT_PAYLOAD_LENGTH: felt252 = 'INVALID_DEPOSIT_PAYLOAD_LENGTH';
pub const INVALID_ZERO_ADDRESS: felt252 = 'INVALID_ZERO_ADDRESS';
pub const SAME_VALIDATION_THRESHOLD: felt252 = 'SAME_VALIDATION_THRESHOLD';

pub fn already_withdrawn(deposit_id: u256, withdrawal_amount: u256) -> ByteArray {
    format!(
        "AlreadyWithdrawn; deposit_id: {:?}, withdrawal_amount: {:?}",
        deposit_id,
        withdrawal_amount,
    )
}

pub fn withdrawal_failed_validation(deposit_id: u256, withdrawal_amount: u256) -> ByteArray {
    format!(
        "WithdrawalFailedValidation; deposit_id: {:?}, withdrawal_amount: {:?}",
        deposit_id,
        withdrawal_amount,
    )
}

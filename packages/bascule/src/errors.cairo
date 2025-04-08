pub const BAD_DEPOSIT_REPORT: felt252 = 'BAD_DEPOSIT_REPORT';
pub const SAME_VALIDATION_THRESHOLD: felt252 = 'SAME_VALIDATION_THRESHOLD';
pub const UNAUTHORIZED_WITHDRAWAL_CALLER: felt252 = 'UNAUTHORIZED_WITHDRAWAL_CALLER';


pub fn already_withdrawn(deposit_id: u256, withdrawal_amount: u128) -> ByteArray {
    format!(
        "AlreadyWithdrawn; deposit_id: {:?}, withdrawal_amount: {:?}",
        deposit_id,
        withdrawal_amount,
    )
}

pub fn Withdrawal_failed_validation(deposit_id: u256, withdrawal_amount: u128) -> ByteArray {
    format!(
        "WithdrawalFailedValidation; deposit_id: {:?}, withdrawal_amount: {:?}",
        deposit_id,
        withdrawal_amount,
    )
}

pub const INVALID_ZERO_ADDRESS: felt252 = 'INVALID_ZERO_ADDRESS';
pub const INVALID_ZERO_DUST_FEE_RATE: felt252 = 'INVALID_ZERO_DUST_FEE_RATE';
pub const SCRIPT_PUB_KEY_UNSUPPORTED: felt252 = 'SCRIPT_PUB_KEY_UNSUPPORTED';
pub const WITHDRAWALS_DISABLED: felt252 = 'WITHDRAWALS_DISABLED';

pub fn amount_below_dust_limit(dust_limit: u128) -> ByteArray {
    format!("AMOUNT_BELOW_DUST_LIMIT dust limit: {:?}", dust_limit)
}

pub fn amount_less_than_commission(fee: u64) -> ByteArray {
    format!("AMOUNT_LESS_THAN_COMMISSION fee: {:?}", fee)
}

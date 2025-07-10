use starkware_utils::math::utils::mul_wide_and_ceil_div;

#[derive(Drop, PartialEq)]
pub enum OutputType {
    UNSUPPORTED,
    P2TR,
    P2WPKH,
    P2WSH,
}

// Default value - 3 satoshis per byte
pub const DEFAULT_DUST_FEE_RATE: u128 = 3000;

const OP_0: u8 = 0x00;
const OP_1: u8 = 0x51;
const OP_DATA_32: u8 = 0x20;
const OP_DATA_20: u8 = 0x14;

// 32 (txid) + 4 (vout) + 1 (scriptSig size) + 4 (nSequence) + 8 (amount)
const BASE_SPEND_COST: u128 = 49;

// Size of inputs spending different output types
// Used for non-witness outputs (P2PKH, P2SH)
const NON_WITNESS_INPUT_SIZE: u32 = 107;
// floor(107 / 4), used for witness outputs (P2WPKH, P2WSH, P2TR)
const WITNESS_INPUT_SIZE: u32 = 26;

pub fn get_output_type(script_pub_key: @ByteArray) -> OutputType {
    const INVALID_SCRIPT_PUB_KEY_LENGHT: felt252 = 'INVALID_SCRIPT_PUB_KEY_LENGHT';

    let len = script_pub_key.len();
    if len < 2 {
        return OutputType::UNSUPPORTED;
    }

    let script_pub_key_0 = script_pub_key.at(0).expect(INVALID_SCRIPT_PUB_KEY_LENGHT);
    let script_pub_key_1 = script_pub_key.at(1).expect(INVALID_SCRIPT_PUB_KEY_LENGHT);

    if len == 22 && script_pub_key_0 == OP_0 && script_pub_key_1 == OP_DATA_20 {
        return OutputType::P2WPKH;
    }

    if len == 34 && script_pub_key_0 == OP_1 && script_pub_key_1 == OP_DATA_32 {
        return OutputType::P2TR;
    }

    if len == 34 && script_pub_key_0 == OP_0 && script_pub_key_1 == OP_DATA_32 {
        return OutputType::P2WSH;
    }

    OutputType::UNSUPPORTED
}

pub fn get_dust_limit_for_output(
    output_type: OutputType, script_pub_key: @ByteArray, dust_fee_rate: u128,
) -> u128 {
    const SHOULD_FIT_IN_U128: felt252 = 'SHOULD_FIT_IN_U128';

    let mut spend_cost = BASE_SPEND_COST;

    match output_type {
        OutputType::P2TR | OutputType::P2WPKH |
        OutputType::P2WSH => {
            // witness v0 and v1 has a cheaper payment formula.
            spend_cost += WITNESS_INPUT_SIZE.into();
            // The current addition creates a discrepancy of 1, and our final value should be 98
            // bytes. Thus, we add 1 here.
            spend_cost += 1;
        },
        _ => { spend_cost += NON_WITNESS_INPUT_SIZE.into(); },
    }

    spend_cost += script_pub_key.len().into();

    mul_wide_and_ceil_div(lhs: spend_cost, rhs: dust_fee_rate, div: 1000).expect(SHOULD_FIT_IN_U128)
}

use lbtc_bascule::utils::build_deposit_payload;
use starknet::ContractAddress;

const U32_IN_BYTES: usize = 4;

/// Public Functions.

/// Adds the selector prefix to the `deposit_payload`.
pub fn build_deposit_payload_with_selector(
    to_chain: u256, recipient: ContractAddress, amount: u256, tx_id: u256, vout: u32,
) -> ByteArray {
    let deposit_payload = build_deposit_payload(:to_chain, :recipient, :amount, :tx_id, :vout);

    // bytes4(keccak256("payload(bytes32,bytes32,uint64,bytes32,uint32)"))
    const DEPOSIT_BTC_ACTION: felt252 = 0xf2e73f7c;

    let mut payload: ByteArray = Default::default();
    payload.append_word(word: DEPOSIT_BTC_ACTION, len: U32_IN_BYTES);
    payload.append(other: @deposit_payload);
    payload
}

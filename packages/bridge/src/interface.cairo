use starknet::ContractAddress;

pub type Proof = Span<(u256, u256)>;

#[starknet::interface]
pub trait IBridge<TContractState> {
    fn change_consortium(ref self: TContractState, new_consortium: ContractAddress);
    fn get_consortium(self: @TContractState) -> ContractAddress;
    fn change_treasury(ref self: TContractState, new_treasury: ContractAddress);
    fn get_treasury(self: @TContractState) -> ContractAddress;
    fn change_burn_commission(ref self: TContractState, new_burn_commission: u64);
    fn get_burn_commission(self: @TContractState) -> u64;

    fn toggle_withdrawals(ref self: TContractState);
    fn set_mint_fee(ref self: TContractState, fee: u128);
    fn change_dust_fee_rate(ref self: TContractState, new_rate: u128);
    fn mint(
        ref self: TContractState,
        to_chain: u128,
        recipient: ContractAddress,
        amount: u128,
        tx_id: u256,
        vout: u32,
        proof: Proof,
    );
    fn redeem(ref self: TContractState, script_public_key: Span<felt252>, amount: u128);

    // getters:
    fn get_mint_fee(self: @TContractState) -> u128;
    fn calc_unstake_request_amount(
        self: @TContractState, script_public_key: Span<felt252>, amount: u128,
    ) -> (u128, bool);
    fn get_dust_fee_rate(self: @TContractState) -> u128;
    fn is_payload_used(
        self: @TContractState, payload_hash: u256, legacy_used_payload_hash: u256,
    ) -> bool;
}

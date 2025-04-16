#[starknet::contract]
pub mod bridge {
    use core::num::traits::Zero;
    use lbtc_bascule::interface::{IBasculeDispatcher, IBasculeDispatcherTrait};
    use lbtc_bridge::interface::{IBridge, Proof};
    use lbtc_bridge::{errors, events};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;


    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[storage]
    struct Storage {
        // --- Components ---
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
        // --- Bridge ---
        bascule: ContractAddress,
        consortium: ContractAddress,
        treasury: ContractAddress,
        burn_commission: u64,
        is_withdrawals_enabled: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        BasculeChanged: events::BasculeChanged,
        ConsortiumChanged: events::ConsortiumChanged,
        TreasuryChanged: events::TreasuryChanged,
        BurnCommissionChanged: events::BurnCommissionChanged,
        WithdrawalsEnabled: events::WithdrawalsEnabled,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        consortium: ContractAddress,
        treasury: ContractAddress,
        burn_commission: u64,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self._change_consortium(new_consortium: consortium);
        self._change_treasury(new_treasury: treasury);
        self._change_burn_commission(new_burn_commission: burn_commission);
    }

    #[abi(embed_v0)]
    pub impl BridgeImpl of IBridge<ContractState> {
        fn set_mint_fee(ref self: ContractState, fee: u128) {}
        fn mint(
            ref self: ContractState,
            to_chain: u128,
            recipient: ContractAddress,
            amount: u128,
            tx_id: u256,
            vout: u32,
            proof: Proof,
        ) {}
        fn redeem(ref self: ContractState, script_public_key: Span<felt252>, amount: u128) {}

        /// ONLY APP_GOVERNOR FUNCTIONS ///

        /// Change the address of the Bascule drawbridge contract.
        /// Setting the address to 0 disables the Bascule check.
        /// @param new_bascule The new address.
        ///
        /// Emits a {BasculeChanged} event.
        fn change_bascule(ref self: ContractState, new_bascule: ContractAddress) {
            self.roles.only_app_governor();
            self._change_bascule(:new_bascule);
        }

        fn change_consortium(ref self: ContractState, new_consortium: ContractAddress) {
            self.roles.only_app_governor();
            self._change_consortium(:new_consortium);
        }

        fn change_treasury(ref self: ContractState, new_treasury: ContractAddress) {
            self.roles.only_app_governor();
            self._change_treasury(:new_treasury);
        }

        fn change_burn_commission(ref self: ContractState, new_burn_commission: u64) {
            self.roles.only_app_governor();
            self._change_burn_commission(:new_burn_commission);
        }

        fn toggle_withdrawals(ref self: ContractState) {
            self.roles.only_app_governor();
            let is_withdrawals_enabled = !(self.is_withdrawals_enabled.read());
            self.is_withdrawals_enabled.write(is_withdrawals_enabled);
            self.emit(events::WithdrawalsEnabled { is_withdrawals_enabled });
        }

        fn change_dust_fee_rate(ref self: ContractState, new_rate: u128) {}

        // Getters:

        fn get_consortium(self: @ContractState) -> ContractAddress {
            self.consortium.read()
        }

        fn get_treasury(self: @ContractState) -> ContractAddress {
            self.treasury.read()
        }
        fn get_burn_commission(self: @ContractState) -> u64 {
            self.burn_commission.read()
        }
        fn get_mint_fee(self: @ContractState) -> u128 {
            Default::default()
        }
        fn calc_unstake_request_amount(
            self: @ContractState, script_public_key: Span<felt252>, amount: u128,
        ) -> (u128, bool) {
            Default::default()
        }
        fn get_dust_fee_rate(self: @ContractState) -> u128 {
            Default::default()
        }
        fn is_payload_used(
            self: @ContractState, payload_hash: u256, legacy_used_payload_hash: u256,
        ) -> bool {
            Default::default()
        }
    }


    #[generate_trait]
    impl PrivateImpl of PrivateBridge {
        fn _change_consortium(ref self: ContractState, new_consortium: ContractAddress) {
            assert(new_consortium.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
            let old_consortium = self.consortium.read();
            self.consortium.write(new_consortium);
            self.emit(events::ConsortiumChanged { old_consortium, new_consortium });
        }

        fn _change_treasury(ref self: ContractState, new_treasury: ContractAddress) {
            assert(new_treasury.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
            let old_treasury = self.treasury.read();
            self.treasury.write(new_treasury);
            self.emit(events::TreasuryChanged { old_treasury, new_treasury });
        }

        fn _change_burn_commission(ref self: ContractState, new_burn_commission: u64) {
            let old_burn_commission = self.burn_commission.read();
            self.burn_commission.write(new_burn_commission);
            self.emit(events::BurnCommissionChanged { old_burn_commission, new_burn_commission });
        }

        /// Change the address of the Bascule drawbridge contract.
        /// @param new_bascule The new address.
        /// Emits a {BasculeChanged} event.
        fn _change_bascule(ref self: ContractState, new_bascule: ContractAddress) {
            let old_bascule = self.bascule.read();
            self.bascule.write(new_bascule);
            self.emit(events::BasculeChanged { old_bascule, new_bascule });
        }

        /// @dev Checks that the deposit was validated by the Bascule drawbridge.
        /// @param deposit_id The unique ID of the deposit.
        /// @param amount The withdrawal amount.
        fn _confirm_deposit(ref self: ContractState, deposit_id: u256, amount: u128) {
            let bascule = self.bascule.read();
            if bascule.is_non_zero() {
                let dispatcher = IBasculeDispatcher { contract_address: bascule };
                dispatcher.validate_withdrawal(deposit_id, amount);
            }
        }
    }
}


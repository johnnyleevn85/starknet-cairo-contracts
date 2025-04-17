#[starknet::contract]
pub mod bridge {
    use core::num::traits::Zero;
    use lbtc_bascule::interface::{IBasculeDispatcher, IBasculeDispatcherTrait};
    use lbtc_bridge::interface::IBridge;
    use lbtc_bridge::{errors, events};
    use lbtc_consortium::interface::{IConsortiumDispatcher, Signature};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StorageMapReadAccess, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::interfaces::mintable_token::{
        IMintableTokenDispatcher, IMintableTokenDispatcherTrait,
    };


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
        bascule: IBasculeDispatcher,
        consortium: IConsortiumDispatcher,
        lbtc_token: IMintableTokenDispatcher,
        treasury: ContractAddress,
        burn_commission: u64,
        is_withdrawals_enabled: bool,
        used_payloads: Map<u256, bool>,
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
        lbtc_token: ContractAddress,
        bascule: ContractAddress,
        consortium: ContractAddress,
        treasury: ContractAddress,
        burn_commission: u64,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self._set_lbtc_token_address(:lbtc_token);
        self._set_bascule_address(new_bascule: bascule);
        self._set_consortium_address(new_consortium: consortium);
        self._set_treasury_address(new_treasury: treasury);
        self._set_burn_commission(new_burn_commission: burn_commission);
    }

    #[abi(embed_v0)]
    pub impl BridgeImpl of IBridge<ContractState> {
        // TODO: Implement
        fn set_mint_fee(ref self: ContractState, fee: u128) {}
        // TODO: Implement
        fn mint(
            ref self: ContractState,
            to_chain: u128,
            recipient: ContractAddress,
            amount: u128,
            tx_id: u256,
            vout: u32,
            proof: Span<Signature>,
        ) {}

        // TODO: Implement
        fn redeem(ref self: ContractState, script_public_key: Span<felt252>, amount: u128) {}

        /// ONLY APP_GOVERNOR FUNCTIONS ///

        fn change_treasury(ref self: ContractState, new_treasury: ContractAddress) {
            self.roles.only_app_governor();
            self._set_treasury_address(:new_treasury);
        }

        fn change_burn_commission(ref self: ContractState, new_burn_commission: u64) {
            self.roles.only_app_governor();
            self._set_burn_commission(:new_burn_commission);
        }

        fn enable_withdrawals(ref self: ContractState) {
            self.roles.only_app_governor();
            self.is_withdrawals_enabled.write(true);
            self.emit(events::WithdrawalsEnabled { is_withdrawals_enabled: true });
        }

        fn disable_withdrawals(ref self: ContractState) {
            self.roles.only_app_governor();
            self.is_withdrawals_enabled.write(false);
            self.emit(events::WithdrawalsEnabled { is_withdrawals_enabled: false });
        }

        // TODO: Implement
        fn change_dust_fee_rate(ref self: ContractState, new_rate: u128) {}

        // Getters:

        fn get_lbtc_token_address(self: @ContractState) -> ContractAddress {
            self.lbtc_token.read().contract_address
        }

        fn get_bascule(self: @ContractState) -> ContractAddress {
            self.bascule.read().contract_address
        }

        fn get_consortium(self: @ContractState) -> ContractAddress {
            self.consortium.read().contract_address
        }

        fn get_treasury(self: @ContractState) -> ContractAddress {
            self.treasury.read()
        }

        fn get_burn_commission(self: @ContractState) -> u64 {
            self.burn_commission.read()
        }

        // TODO: Implement
        fn get_mint_fee(self: @ContractState) -> u128 {
            Default::default()
        }

        // TODO: Implement
        fn calc_unstake_request_amount(
            self: @ContractState, script_public_key: Span<felt252>, amount: u128,
        ) -> (u128, bool) {
            Default::default()
        }

        // TODO: Implement
        fn get_dust_fee_rate(self: @ContractState) -> u128 {
            Default::default()
        }

        fn is_payload_used(self: @ContractState, payload_hash: u256) -> bool {
            self.used_payloads.read(payload_hash)
        }
    }


    #[generate_trait]
    impl PrivateImpl of PrivateBridge {
        fn _set_consortium_address(ref self: ContractState, new_consortium: ContractAddress) {
            assert(new_consortium.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
            let old_consortium = self.consortium.read().contract_address;
            self.consortium.write(IConsortiumDispatcher { contract_address: new_consortium });
            self.emit(events::ConsortiumChanged { old_consortium, new_consortium });
        }

        fn _set_treasury_address(ref self: ContractState, new_treasury: ContractAddress) {
            assert(new_treasury.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
            let old_treasury = self.treasury.read();
            self.treasury.write(new_treasury);
            self.emit(events::TreasuryChanged { old_treasury, new_treasury });
        }

        fn _set_burn_commission(ref self: ContractState, new_burn_commission: u64) {
            let old_burn_commission = self.burn_commission.read();
            self.burn_commission.write(new_burn_commission);
            self.emit(events::BurnCommissionChanged { old_burn_commission, new_burn_commission });
        }

        fn _set_lbtc_token_address(ref self: ContractState, lbtc_token: ContractAddress) {
            assert(lbtc_token.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
            self.lbtc_token.write(IMintableTokenDispatcher { contract_address: lbtc_token });
        }

        /// Change the address of the Bascule drawbridge contract.
        /// @param new_bascule The new address.
        /// Emits a {BasculeChanged} event.
        fn _set_bascule_address(ref self: ContractState, new_bascule: ContractAddress) {
            assert(new_bascule.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
            let old_bascule = self.bascule.read().contract_address;
            self.bascule.write(IBasculeDispatcher { contract_address: new_bascule });
            self.emit(events::BasculeChanged { old_bascule, new_bascule });
        }

        /// @dev Checks that the deposit was validated by the Bascule drawbridge.
        /// @param deposit_id The unique ID of the deposit.
        /// @param amount The withdrawal amount.
        fn _confirm_deposit(ref self: ContractState, deposit_id: u256, amount: u128) {
            let bascule = self.bascule.read();
            bascule.validate_withdrawal(deposit_id, amount);
        }
    }
}


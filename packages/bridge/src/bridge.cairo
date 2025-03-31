#[starknet::contract]
pub mod bridge {
    use core::num::traits::Zero;
    use lbtc_bridge::interface::IBridge;
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
        consortium: ContractAddress,
        treasury: ContractAddress,
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
        ConsortiumChanged: events::ConsortiumChanged,
        TreasuryChanged: events::TreasuryChanged,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState, governance_admin: ContractAddress, upgrade_delay: u64,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
    }

    #[abi(embed_v0)]
    pub impl BridgeImpl of IBridge<ContractState> {
        fn change_consortium(ref self: ContractState, new_consortium: ContractAddress) {
            self._change_consortium(:new_consortium);
        }

        fn get_consortium(self: @ContractState) -> ContractAddress {
            self.consortium.read()
        }
        fn change_treasury(ref self: ContractState, new_treasury: ContractAddress) {
            self._change_treasury(:new_treasury);
        }

        fn get_treasury(self: @ContractState) -> ContractAddress {
            self.treasury.read()
        }
    }


    #[generate_trait]
    impl PrivateImpl of PrivateBridge {
        fn _change_consortium(ref self: ContractState, new_consortium: ContractAddress) {
            self.roles.only_app_governor();
            assert(new_consortium.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
            let old_consortium = self.consortium.read();
            self.consortium.write(new_consortium);
            self.emit(events::ConsortiumChanged { old_consortium, new_consortium });
        }

        fn _change_treasury(ref self: ContractState, new_treasury: ContractAddress) {
            self.roles.only_app_governor();
            assert(new_treasury.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
            let old_treasury = self.treasury.read();
            self.treasury.write(new_treasury);
            self.emit(events::TreasuryChanged { old_treasury, new_treasury });
        }
    }
}


#[starknet::contract]
pub mod bascule {
    use lbtc_bascule::types::DepositState;
    use lbtc_bascule::{errors, events};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::event::EventEmitter;
    use starknet::storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::components::roles::interface::SECURITY_AGENT;


    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        /// Maximum number of batch deposits it's possible to make at once
        max_deposits: u32,
        validate_threshold: u128,
        depositHistory: Map<felt252, DepositState>,
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
        DepositAlreadyReported: events::DepositAlreadyReported,
        DepositsReported: events::DepositsReported,
        MaxDepositsUpdated: events::MaxDepositsUpdated,
        UpdateValidateThreshold: events::UpdateValidateThreshold,
        WithdrawalNotValidated: events::WithdrawalNotValidated,
        WithdrawalValidated: events::WithdrawalValidated,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState, governance_admin: ContractAddress, max_deposits: u32,
    ) {
        self.roles.initialize(:governance_admin);
        self.max_deposits.write(max_deposits);
    }
    use lbtc_bascule::interface::IBascule;

    #[abi(embed_v0)]
    pub impl BasculeImpl of IBascule<ContractState> {
        fn validate_withdrawal(
            ref self: ContractState, deposit_id: felt252, withdrawal_amount: u128,
        ) {}
        /// Updates the threshold for checking validation withdrawals.
        /// Only app governors can call this function.
        ///
        /// Lowering the threshold means we validate more deposits;
        /// Increasing the threshold means we validate fewer
        /// deposits;
        ///
        /// # Emits
        /// * `UpdateValidateThreshold` with the old and new thresholds.
        fn update_validation_threshold(ref self: ContractState, new_threshold: u128) {
            self.pausable.assert_not_paused();
            self.roles.only_app_governor();

            let old_threshold = self.get_validate_threshold();
            assert(old_threshold != new_threshold, errors::SAME_VALIDATION_THRESHOLD);

            self.validate_threshold.write(new_threshold);
            self
                .emit(
                    events::UpdateValidateThreshold {
                        old_threshold: old_threshold, new_threshold: new_threshold,
                    },
                );
        }
        /// View functions

        ///  Returns the minimum threshold for validating withdrawals.
        fn get_validate_threshold(self: @ContractState) -> u128 {
            self.validate_threshold.read()
        }
        /// Get maximum number of deposits that can be reported at once.
        fn get_max_deposits(self: @ContractState) -> u32 {
            self.max_deposits.read()
        }
    }
}


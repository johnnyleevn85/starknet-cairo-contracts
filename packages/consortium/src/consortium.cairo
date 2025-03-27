#[starknet::contract]
pub mod consortium {
    use lbtc_consortium::events::ValidatorSetUpdated;
    use lbtc_consortium::interface::IConsortium;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StoragePointerReadAccess};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::iterable_map::IterableMap;
    use starkware_utils::types::{PublicKey, Signature};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    #[starknet::storage_node]
    pub struct ValidatorSet {
        // The public keys of the validators and their corresponding weights.
        pub validators: IterableMap<PublicKey, u128>,
        pub weight_threshold: u128,
    }

    #[storage]
    struct Storage {
        epoch: u64,
        validator_set_map: Map<u64, ValidatorSet>,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        pub replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        ValidatorSetUpdated: ValidatorSetUpdated,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState, governance_admin: ContractAddress, upgrade_delay: u64,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
    }

    #[abi(embed_v0)]
    pub impl ConsortiumImpl of IConsortium<ContractState> {
        fn set_initial_validator_set(
            ref self: ContractState,
            validator_pks: Array<PublicKey>,
            weights: Array<u128>,
            weight_threshold: u128,
        ) {}

        fn set_next_validator_set(
            ref self: ContractState,
            validator_pks: Array<PublicKey>,
            weights: Array<u128>,
            weight_threshold: u128,
            proof: Array<Signature>,
            signer_pks: Array<PublicKey>,
        ) {}

        fn check_proof(
            self: @ContractState,
            payload_hash: felt252,
            proof: Array<Signature>,
            signer_pks: Array<PublicKey>,
        ) {}

        fn get_validator_set(
            self: @ContractState, epoch: u64,
        ) -> (Array<PublicKey>, Array<u128>, u128) {
            Default::default()
        }

        fn get_current_epoch(self: @ContractState) -> u64 {
            self.epoch.read()
        }
    }
}

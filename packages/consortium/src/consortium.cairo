#[starknet::contract]
pub mod consortium {
    use core::dict::Felt252Dict;
    use core::num::traits::Zero;
    use lbtc_consortium::errors::{
        INVALID_EPOCH, INVALID_SIGNATURE, INVALID_VALIDATOR_SET_SIZE, INVALID_ZERO_WEIGHT,
        INVALID_ZERO_WEIGHT_THRESHOLD, NOT_ENOUGH_SIGNATURES, TOTAL_WEIGHT_UNDER_THRESHOLD,
        VALIDATORS_ALREADY_INITIALIZED, VALIDATORS_PROOF_LEN_MISMATCH,
        VALIDATORS_WEIGHTS_LEN_MISMATCH, VALIDATORS_WERE_NOT_INITIALIZED,
    };
    use lbtc_consortium::events::ValidatorSetUpdated;
    use lbtc_consortium::interface::{IConsortium, Signature};
    use lbtc_consortium::utils::{
        deprecated_calculate_hash_for_next_validators, ensure_uniqueness, is_signature_by_signer,
    };
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::eth_address::EthAddress;
    use starknet::secp256_trait::Signature as Secp256Signature;
    use starknet::storage::{
        Map, MutableVecTrait, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
        Vec, VecTrait,
    };
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;

    const MIN_VALIDATOR_SET_SIZE: u32 = 1;
    const MAX_VALIDATOR_SET_SIZE: u32 = 25;

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[starknet::storage_node]
    pub struct ValidatorSet {
        // Address weight tuples.
        pub validators: Vec<(EthAddress, u128)>,
        // Current threshold for signatures weight to be accepted.
        pub threshold_weight: u128,
    }

    #[storage]
    struct Storage {
        epoch: u64,
        validator_set_map: Map<u64, ValidatorSet>,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
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
            validators: Array<EthAddress>,
            weights: Array<u128>,
            threshold_weight: u128,
        ) {
            self.roles.only_app_governor();

            // Validations.
            assert(self.epoch.read().is_zero(), VALIDATORS_ALREADY_INITIALIZED);
            self
                ._validate_new_validator_set(
                    validators: @validators, weights: @weights, :threshold_weight,
                );

            self._set_validator_set(epoch: 1, :validators, :weights, :threshold_weight);
        }

        fn set_next_validator_set(
            ref self: ContractState,
            epoch: u64,
            validators: Array<EthAddress>,
            weights: Array<u128>,
            threshold_weight: u128,
            height: u128,
            proof: Array<Signature>,
        ) {
            // Validations.
            let cur_epoch = self.epoch.read();
            assert(cur_epoch + 1 == epoch, INVALID_EPOCH);
            self
                ._validate_new_validator_set(
                    validators: @validators, weights: @weights, :threshold_weight,
                );

            let msg_hash = deprecated_calculate_hash_for_next_validators(
                :epoch, validators: @validators, weights: @weights, :threshold_weight, :height,
            );
            self.check_proof(:msg_hash, :proof);

            self._set_validator_set(:epoch, :validators, :weights, :threshold_weight);
        }

        fn check_proof(self: @ContractState, msg_hash: u256, proof: Array<Signature>) {
            let epoch = self.get_current_epoch();
            assert(epoch.is_non_zero(), VALIDATORS_WERE_NOT_INITIALIZED);

            let validator_set = self.validator_set_map.entry(epoch);
            assert(
                validator_set.validators.len() == proof.len().into(), VALIDATORS_PROOF_LEN_MISMATCH,
            );

            let mut total_weight = 0;
            let mut i = 0;
            for signature in proof {
                // Check signature.
                let (r, s) = signature;
                if r == 0 && s == 0 {
                    continue;
                }
                let (validator, weight) = validator_set.validators[i].read();
                let signature_y_parity_true = Secp256Signature { r, s, y_parity: true };
                let is_signed_by_validator = is_signature_by_signer(
                    signer: validator, :msg_hash, signature: signature_y_parity_true,
                );
                // In case the signature with y parity true doesnt belong to the validator, check
                // signature with y parity false.
                if !is_signed_by_validator {
                    let signature_y_parity_false = Secp256Signature { r, s, y_parity: false };
                    assert(
                        is_signature_by_signer(
                            signer: validator, :msg_hash, signature: signature_y_parity_false,
                        ),
                        INVALID_SIGNATURE,
                    );
                }

                total_weight += weight;
                i += 1;
            }

            let threshold_weight = validator_set.threshold_weight.read();
            assert(total_weight >= threshold_weight, NOT_ENOUGH_SIGNATURES);
        }

        fn get_validator_set(
            self: @ContractState, epoch: u64,
        ) -> (Array<EthAddress>, Array<u128>, u128) {
            let validator_set = self.validator_set_map.entry(epoch);
            let threshold_weight = validator_set.threshold_weight.read();
            assert(threshold_weight.is_non_zero(), INVALID_EPOCH);

            let mut validators = array![];
            let mut weights = array![];
            for i in 0..validator_set.validators.len() {
                let (validator, weight) = validator_set.validators[i].read();
                validators.append(validator);
                weights.append(weight);
            }

            (validators, weights, threshold_weight)
        }

        fn get_current_epoch(self: @ContractState) -> u64 {
            self.epoch.read()
        }
    }

    #[generate_trait]
    impl ConsortiumPrivateImpl of ConsortiumPrivateTrait {
        fn _validate_new_validator_set(
            ref self: ContractState,
            validators: @Array<EthAddress>,
            weights: @Array<u128>,
            threshold_weight: u128,
        ) {
            assert(threshold_weight.is_non_zero(), INVALID_ZERO_WEIGHT_THRESHOLD);
            assert(validators.len() == weights.len(), VALIDATORS_WEIGHTS_LEN_MISMATCH);

            let validator_set_size = validators.len();
            assert(validator_set_size >= MIN_VALIDATOR_SET_SIZE, INVALID_VALIDATOR_SET_SIZE);
            assert(validator_set_size <= MAX_VALIDATOR_SET_SIZE, INVALID_VALIDATOR_SET_SIZE);
        }

        fn _set_validator_set(
            ref self: ContractState,
            epoch: u64,
            validators: Array<EthAddress>,
            weights: Array<u128>,
            threshold_weight: u128,
        ) {
            let mut validator_set = self.validator_set_map.entry(epoch);
            let mut total_weight = 0;
            let mut address_dict: Felt252Dict<bool> = Default::default();
            for i in 0..validators.len() {
                let weight = *weights[i];
                assert(weight.is_non_zero(), INVALID_ZERO_WEIGHT);

                let validator = *validators[i];
                ensure_uniqueness(ref :address_dict, eth_address: validator);
                validator_set.validators.push((validator, weight));

                total_weight = total_weight + weight;
            }

            assert(total_weight >= threshold_weight, TOTAL_WEIGHT_UNDER_THRESHOLD);
            validator_set.threshold_weight.write(threshold_weight);
            self.epoch.write(epoch);

            // Emit event.
            self
                .emit(
                    ValidatorSetUpdated { epoch, validators, weights, threshold: threshold_weight },
                );
        }
    }
}

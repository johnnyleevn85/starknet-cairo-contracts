#[starknet::contract]
pub mod consortium {
    use core::dict::Felt252Dict;
    use core::num::traits::Zero;
    use lbtc_consortium::errors::*;
    use lbtc_consortium::events::ValidatorSetUpdated;
    use lbtc_consortium::interface::{IConsortium, PublicKey, Signature};
    use lbtc_consortium::utils::{
        calculate_sha256_for_set_next_validator_set_paylod, ensure_uniqueness,
    };
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::eth_address::EthAddress;
    use starknet::eth_signature::public_key_point_to_eth_address;
    use starknet::secp256_trait::{Secp256Trait, Signature as Secp256Signature, recover_public_key};
    use starknet::secp256k1::Secp256k1Point;
    use starknet::storage::{
        Map, StoragePath, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, SyscallResultTrait};
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::iterable_map::{
        IterableMap, IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };

    const INITIAL_EPOCH: u64 = 1;
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
        address_to_weight: IterableMap<EthAddress, u128>,
        // Current threshold for signatures weight to be accepted.
        pub threshold_weight: u128,
    }

    #[storage]
    struct Storage {
        epoch: u64,
        epoch_to_validator_set: Map<u64, ValidatorSet>,
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
            public_keys: Span<PublicKey>,
            weights: Span<u128>,
            threshold_weight: u128,
        ) {
            self.roles.only_app_governor();
            self
                ._validate_new_validator_set(
                    epoch: INITIAL_EPOCH, :public_keys, :weights, :threshold_weight,
                );
            self
                ._set_validator_set(
                    epoch: INITIAL_EPOCH, :public_keys, :weights, :threshold_weight,
                );
        }

        fn set_next_validator_set(
            ref self: ContractState,
            epoch: u64,
            public_keys: Span<PublicKey>,
            weights: Span<u128>,
            threshold_weight: u128,
            height: u128,
            proof: Span<Signature>,
        ) {
            // Validations.
            self._validate_new_validator_set(:epoch, :public_keys, :weights, :threshold_weight);

            let msg_hash = calculate_sha256_for_set_next_validator_set_paylod(
                :epoch, :public_keys, :weights, :threshold_weight, :height,
            );
            self.check_proof(:msg_hash, :proof);

            self._set_validator_set(:epoch, :public_keys, :weights, :threshold_weight);
        }

        fn check_proof(self: @ContractState, msg_hash: u256, proof: Span<Signature>) {
            let epoch = self.get_current_epoch();
            assert(epoch.is_non_zero(), VALIDATORS_WERE_NOT_INITIALIZED);

            let validator_set = self.epoch_to_validator_set.entry(epoch);
            let threshold_weight = validator_set.threshold_weight.read();

            let mut address_set: Felt252Dict<bool> = Default::default();
            let mut total_weight = 0;
            for signature in proof {
                // Check signature.
                if *signature == (0, 0) {
                    continue;
                }

                if let Some((eth_address, weight)) =
                    _verify_signature_and_get_validator_weight(
                        :validator_set, :signature, :msg_hash,
                    ) {
                    // Check if the address is already signed.
                    ensure_uniqueness(ref :address_set, :eth_address, error: DUPLICATED_SIGNATURE);
                    total_weight += weight;
                }

                // Early break.
                if total_weight >= threshold_weight {
                    break;
                }
            }

            assert(total_weight >= threshold_weight, NOT_ENOUGH_SIGNATURES);
        }

        fn get_validator_set(
            self: @ContractState, epoch: u64,
        ) -> (Span<EthAddress>, Span<u128>, u128) {
            let validator_set = self.epoch_to_validator_set.entry(epoch);
            let threshold_weight = validator_set.threshold_weight.read();
            assert(threshold_weight.is_non_zero(), INVALID_EPOCH);

            let mut validators = array![];
            let mut weights = array![];
            for (validator, weight) in validator_set.address_to_weight {
                validators.append(validator);
                weights.append(weight);
            }

            (validators.span(), weights.span(), threshold_weight)
        }

        fn get_current_epoch(self: @ContractState) -> u64 {
            self.epoch.read()
        }
    }

    #[generate_trait]
    impl ConsortiumPrivateImpl of ConsortiumPrivateTrait {
        fn _validate_new_validator_set(
            ref self: ContractState,
            epoch: u64,
            public_keys: Span<PublicKey>,
            weights: Span<u128>,
            threshold_weight: u128,
        ) {
            let cur_epoch = self.epoch.read();
            let next_epoch = cur_epoch + 1;
            assert(next_epoch == epoch, INVALID_EPOCH);
            assert(threshold_weight.is_non_zero(), INVALID_ZERO_WEIGHT_THRESHOLD);
            let validator_set_size = public_keys.len();
            assert(validator_set_size == weights.len(), PUB_KEYS_WEIGHTS_LEN_MISMATCH);
            assert(validator_set_size >= MIN_VALIDATOR_SET_SIZE, INVALID_VALIDATOR_SET_SIZE);
            assert(validator_set_size <= MAX_VALIDATOR_SET_SIZE, INVALID_VALIDATOR_SET_SIZE);
        }

        fn _set_validator_set(
            ref self: ContractState,
            epoch: u64,
            public_keys: Span<PublicKey>,
            weights: Span<u128>,
            threshold_weight: u128,
        ) {
            let mut validator_set = self.epoch_to_validator_set.entry(epoch);
            let mut total_weight = 0;
            let mut eth_addresses: Array<EthAddress> = Default::default();
            let mut address_set: Felt252Dict<bool> = Default::default();

            for i in 0..public_keys.len() {
                let weight = *weights[i];
                assert(weight.is_non_zero(), INVALID_ZERO_WEIGHT);

                // Generate eth address from public key.
                let (x, y) = *public_keys[i];
                let secp_point = Secp256Trait::<Secp256k1Point>::secp256_ec_new_syscall(x, y)
                    .unwrap_syscall()
                    .expect(INVALID_PUBLIC_KEY);
                let eth_address = public_key_point_to_eth_address(secp_point);

                ensure_uniqueness(ref :address_set, :eth_address, error: DUPLICATED_VALIDATOR);
                eth_addresses.append(eth_address);
                validator_set.address_to_weight.write(eth_address, weight);

                total_weight = total_weight + weight;
            }

            assert(total_weight >= threshold_weight, TOTAL_WEIGHT_UNDER_THRESHOLD);
            validator_set.threshold_weight.write(threshold_weight);
            self.epoch.write(epoch);

            // Emit event.
            self
                .emit(
                    ValidatorSetUpdated {
                        epoch,
                        validators: eth_addresses.span(),
                        weights,
                        threshold: threshold_weight,
                    },
                );
        }
    }

    /// Verifies if the signer of a signature (with either parity value) is in `validator_set`.
    ///
    /// This function tries both `y_parity=true` and `y_parity=false` to validate the signature.
    ///
    /// @param validator_set - map for the validator set.
    /// @param r - The r component of the signature
    /// @param s - The s component of the signature
    /// @param msg_hash - The hash of the message that was signed
    /// @return address whether the signature is valid and for a validator in the set.
    fn _verify_signature_and_get_validator_weight(
        validator_set: StoragePath<ValidatorSet>, signature: @Signature, msg_hash: u256,
    ) -> Option<(EthAddress, u128)> {
        let (r, s) = *signature;
        // Try with y_parity = true first
        let signature = Secp256Signature { r, s, y_parity: true };
        let address_weight = _verify_signature_and_get_validator_weight_inner(
            :validator_set, :signature, :msg_hash,
        );
        if address_weight.is_some() {
            return address_weight;
        }

        // If that failed, try with y_parity = false.
        let signature = Secp256Signature { r, s, y_parity: false };
        _verify_signature_and_get_validator_weight_inner(:validator_set, :signature, :msg_hash)
    }

    fn _verify_signature_and_get_validator_weight_inner(
        validator_set: StoragePath<ValidatorSet>, signature: Secp256Signature, msg_hash: u256,
    ) -> Option<(EthAddress, u128)> {
        let public_key_point = recover_public_key::<Secp256k1Point>(:msg_hash, :signature)?;
        let address = public_key_point_to_eth_address(:public_key_point);
        let weight = validator_set.address_to_weight.read(address)?;
        Some((address, weight))
    }
}

#[starknet::contract]
pub mod bascule {
    use core::num::traits::Zero;
    use lbtc_bascule::interface::{DepositState, IBascule};
    use lbtc_bascule::utils::calculate_deposit_id;
    use lbtc_bascule::{errors, events};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::access::accesscontrol::AccessControlComponent::{
        DEFAULT_ADMIN_ROLE, InternalTrait as AccessControlInternal,
    };
    use openzeppelin::access::accesscontrol::interface::IAccessControl;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::security::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starknet::event::EventEmitter;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::pausable::interface::IPausable;
    use starkware_utils::errors::assert_with_byte_array;


    const DEPOSIT_REPORTER: felt252 = selector!("DEPOSIT_REPORTER_ROLE");
    const WITHDRAWAL_VALIDATOR: felt252 = selector!("WITHDRAWAL_VALIDATOR_ROLE");
    const VALIDATION_GUARDIAN: felt252 = selector!("VALIDATION_GUARDIAN_ROLE");
    const PAUSER: felt252 = selector!("PAUSER_ROLE");

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    impl PausableImplOZ = PausableComponent::PausableImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        /// Maximum number of batch deposits it's possible to make at once
        max_deposits: u32,
        /// The bascule validates all withdrawals whose amounts are greater than or
        /// equal to this threshold. The bascule allows all withdrawals below this
        /// threshold. The contract will still produce events that off-chain code can
        /// use to monitor smaller withdrawals. This threshold can only be changed by
        /// the app governor.
        ///
        /// When the threshold is zero (the default), the bascule validates all
        /// withdrawals.
        ///
        /// NOTE: Raising this threshold should be done with extreme caution.  In
        /// particular, you MUST make sure that validate_withdrawal is called with a
        /// correct withdrawal amount.
        validate_threshold: u256,
        /// Mapping that tracks deposits on a different chain that can be used to
        /// withdraw the corresponding funds on this chain.
        ///
        /// NOTE: The deposit identifier should be a hash with enough information to
        /// uniquely identify the deposit transaction on the source chain and the
        /// recipient, amount, and chain-id on this chain.
        deposit_status: Map<u256, DepositState>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
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
        ref self: ContractState,
        governance_admin: ContractAddress,
        pauser: ContractAddress,
        deposit_reporter: ContractAddress,
        withdrawal_validator: ContractAddress,
        max_deposits: u32,
    ) {
        // Validate addresses are non-zero
        assert(governance_admin.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
        assert(pauser.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
        assert(deposit_reporter.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
        assert(withdrawal_validator.is_non_zero(), errors::INVALID_ZERO_ADDRESS);

        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(role: DEFAULT_ADMIN_ROLE, account: governance_admin);
        self.accesscontrol._grant_role(role: DEPOSIT_REPORTER, account: deposit_reporter);
        self.accesscontrol._grant_role(role: WITHDRAWAL_VALIDATOR, account: withdrawal_validator);
        self.accesscontrol._grant_role(role: PAUSER, account: pauser);

        self.max_deposits.write(max_deposits);
    }

    #[abi(embed_v0)]
    pub impl BasculeImpl of IBascule<ContractState> {
        // Validate a withdrawal (before executing it) if the amount is above
        // threshold.
        //
        // This function checks if our accounting has recorded a deposit that
        // corresponds to this withdrawal request. A deposit can only be withdrawn
        // once.
        //
        // Emits {WithdrawalValidated, WithdrawalNotValidated}.
        fn validate_withdrawal(
            ref self: ContractState,
            to_chain: u256,
            recipient: ContractAddress,
            withdrawal_amount: u256,
            tx_id: u256,
            vout: u32,
        ) {
            self.pausable.assert_not_paused();
            self.accesscontrol.assert_only_role(role: WITHDRAWAL_VALIDATOR);

            let deposit_id = calculate_deposit_id(
                :to_chain, :recipient, :withdrawal_amount, :tx_id, :vout,
            );
            let deposit_id_entry = self.deposit_status.entry(deposit_id);
            let status = deposit_id_entry.read();
            if status == DepositState::Reported {
                deposit_id_entry.write(DepositState::Withdrawn);
                self.emit(events::WithdrawalValidated { deposit_id, withdrawal_amount });
                return;
            }

            // Already withdrawn
            assert_with_byte_array(
                status != DepositState::Withdrawn,
                errors::already_withdrawn(:deposit_id, :withdrawal_amount),
            );

            // Not reported
            // We disallow a withdrawal if it's not in the deposit_status and
            // the value is above or equal to the threshold.
            assert_with_byte_array(
                withdrawal_amount < self.get_validation_threshold(),
                errors::withdrawal_failed_validation(:deposit_id, :withdrawal_amount),
            );

            // We don't have the deposit_id in the deposit_status, and the value of the
            // withdrawal is below the threshold, so we allow the withdrawal without
            // additional on-chain validation.
            //
            // This contract records withdrawals even when the validation threshold is raised.
            deposit_id_entry.write(DepositState::Withdrawn);
            self.emit(events::WithdrawalNotValidated { deposit_id, withdrawal_amount })
        }
        /// Updates the threshold for checking validation withdrawals.
        /// Only app governors can call this function.
        ///
        /// Lowering the threshold means we validate more deposits;
        /// Increasing the threshold means we validate fewer deposits;
        ///
        /// # Emits
        /// * `UpdateValidateThreshold` with the old and new thresholds.
        fn update_validation_threshold(ref self: ContractState, new_threshold: u256) {
            self.pausable.assert_not_paused();
            let old_threshold = self.get_validation_threshold();
            assert(old_threshold != new_threshold, errors::SAME_VALIDATION_THRESHOLD);

            if new_threshold < old_threshold {
                self.accesscontrol.assert_only_role(role: DEFAULT_ADMIN_ROLE);
            } else {
                self.accesscontrol.assert_only_role(role: VALIDATION_GUARDIAN);
                // Renounce the validation guardian role. This ensures the caller doesn't
                // have peristent privileges to effectively disable validation.
                self
                    .accesscontrol
                    .renounce_role(role: VALIDATION_GUARDIAN, account: get_caller_address());
            }

            self.validate_threshold.write(new_threshold);
            self.emit(events::UpdateValidateThreshold { old_threshold, new_threshold });
        }

        fn set_max_deposits(ref self: ContractState, max_deposits: u32) {
            self.pausable.assert_not_paused();
            self.accesscontrol.assert_only_role(role: DEFAULT_ADMIN_ROLE);
            self.max_deposits.write(max_deposits);
            self.emit(events::MaxDepositsUpdated { num_deposits: max_deposits });
        }


        //  Report that a series of deposit has happened.
        //  May only be invoked by the operator role
        //  @param report_id Unique identifier corresponding to the report.
        //  @param deposit_ids Unique identifiers of the deposits on another chain.
        //  Emits {DepositsReported}.
        fn report_deposits(ref self: ContractState, report_id: u256, deposit_ids: Span<u256>) {
            self.pausable.assert_not_paused();
            self.accesscontrol.assert_only_role(role: DEPOSIT_REPORTER);

            let deposit_ids_len = deposit_ids.len();
            assert(deposit_ids_len <= self.get_max_deposits().into(), errors::BAD_DEPOSIT_REPORT);

            for deposit_id in deposit_ids {
                let deposit_id_entry = self.deposit_status.entry(*deposit_id);
                if deposit_id_entry.read() == DepositState::Unreported {
                    deposit_id_entry.write(DepositState::Reported);
                } else {
                    // Only warn instead of reverting.
                    self.emit(events::DepositAlreadyReported { deposit_id: *deposit_id })
                }
            }
            self.emit(events::DepositsReported { report_id, num_deposits: deposit_ids_len })
        }

        // View functions

        /// Returns the minimum threshold for validating withdrawals.
        fn get_validation_threshold(self: @ContractState) -> u256 {
            self.validate_threshold.read()
        }
        /// Returns the maximum number of deposits that can be reported at once.
        fn get_max_deposits(self: @ContractState) -> u32 {
            self.max_deposits.read()
        }

        /// Returns the deposit status.
        fn get_deposit_status(self: @ContractState, deposit_id: u256) -> DepositState {
            self.deposit_status.entry(deposit_id).read()
        }

        // Role functions

        fn is_deposit_reporter(self: @ContractState, account: ContractAddress) -> bool {
            self.accesscontrol.has_role(role: DEPOSIT_REPORTER, :account)
        }

        fn is_withdrawal_validator(self: @ContractState, account: ContractAddress) -> bool {
            self.accesscontrol.has_role(role: WITHDRAWAL_VALIDATOR, :account)
        }

        fn is_validation_guardian(self: @ContractState, account: ContractAddress) -> bool {
            self.accesscontrol.has_role(role: VALIDATION_GUARDIAN, :account)
        }

        fn is_pauser(self: @ContractState, account: ContractAddress) -> bool {
            self.accesscontrol.has_role(role: PAUSER, :account)
        }

        fn register_deposit_reporter(ref self: ContractState, account: ContractAddress) {
            assert(account.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
            self.accesscontrol.grant_role(role: DEPOSIT_REPORTER, :account);
        }

        fn register_withdrawal_validator(ref self: ContractState, account: ContractAddress) {
            assert(account.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
            self.accesscontrol.grant_role(role: WITHDRAWAL_VALIDATOR, :account);
        }

        fn register_validation_guardian(ref self: ContractState, account: ContractAddress) {
            assert(account.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
            self.accesscontrol.grant_role(role: VALIDATION_GUARDIAN, :account);
        }

        fn register_pauser(ref self: ContractState, account: ContractAddress) {
            assert(account.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
            self.accesscontrol.grant_role(role: PAUSER, :account);
        }

        fn remove_deposit_reporter(ref self: ContractState, account: ContractAddress) {
            self.accesscontrol.revoke_role(role: DEPOSIT_REPORTER, :account);
        }

        fn remove_withdrawal_validator(ref self: ContractState, account: ContractAddress) {
            self.accesscontrol.revoke_role(role: WITHDRAWAL_VALIDATOR, :account);
        }

        fn remove_validation_guardian(ref self: ContractState, account: ContractAddress) {
            self.accesscontrol.revoke_role(role: VALIDATION_GUARDIAN, :account);
        }

        fn remove_pauser(ref self: ContractState, account: ContractAddress) {
            self.accesscontrol.revoke_role(role: PAUSER, :account);
        }
    }

    #[abi(embed_v0)]
    pub impl PausableImpl of IPausable<ContractState> {
        fn is_paused(self: @ContractState) -> bool {
            self.pausable.is_paused()
        }

        fn pause(ref self: ContractState) {
            self.accesscontrol.assert_only_role(role: PAUSER);
            self.pausable.pause();
        }

        fn unpause(ref self: ContractState) {
            self.accesscontrol.assert_only_role(role: PAUSER);
            self.pausable.unpause();
        }
    }
}

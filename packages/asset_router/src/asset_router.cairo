#[starknet::contract]
pub mod asset_router {
    use core::num::traits::{Pow, Zero};
    use core::sha256::compute_sha256_byte_array;
    use lbtc_asset_router::bitcoin_utils::{
        DEFAULT_DUST_FEE_RATE, OutputType, get_dust_limit_for_output, get_output_type,
    };
    use lbtc_asset_router::interface::IAssetRouter;
    use lbtc_asset_router::utils::build_deposit_payload_with_selector;
    use lbtc_asset_router::{errors, events};
    use lbtc_bascule::interface::{IBasculeDispatcher, IBasculeDispatcherTrait};
    use lbtc_consortium::interface::{IConsortiumDispatcher, IConsortiumDispatcherTrait, Signature};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_tx_info};
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::errors::assert_with_byte_array;
    use starkware_utils::interfaces::mintable_token::{
        IMintableTokenDispatcher, IMintableTokenDispatcherTrait,
    };
    use starkware_utils::math::utils::u256_from_u32_array;
    use starkware_utils::storage::utils::AddToStorage;

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[storage]
    struct Storage {
        // --- Components ---
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
        // --- AssetRouter ---
        bascule: IBasculeDispatcher,
        consortium: IConsortiumDispatcher,
        lbtc_token: IMintableTokenDispatcher,
        treasury: ContractAddress,
        burn_commission: u64,
        is_withdrawals_enabled: bool,
        used_payloads: Map<u256, bool>,
        dust_fee_rate: u128,
        btc_locked_amount: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
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
        UnstakeRequest: events::UnstakeRequest,
        DustFeeRateChanged: events::DustFeeRateChanged,
        MintProofConsumed: events::MintProofConsumed,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        bascule: ContractAddress,
        consortium: ContractAddress,
        lbtc_token: ContractAddress,
        treasury: ContractAddress,
        burn_commission: u64,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self._set_bascule_address(new_bascule: bascule);
        self._set_consortium_address(new_consortium: consortium);
        self._set_lbtc_token_address(:lbtc_token);
        self._set_treasury_address(new_treasury: treasury);
        self._set_burn_commission(new_burn_commission: burn_commission);
        self._change_dust_fee_rate(new_rate: DEFAULT_DUST_FEE_RATE);
        // Reset the locked BTC amount to 0.
        self.btc_locked_amount.write(0);
    }

    // 0x0400000000000000000000000000000000000000000000000000000000000000
    // This is the identifier that Lombard uses for Starknet.
    const LOMBARD_STARKNET_IDENTIFIER: u256 = 4 * 16_u256.pow(62);

    const MAX_FEE: u64 = 100000;

    struct FeeDustInfo {
        amount_after_fee: u256,
        is_above_fee: bool,
        dust_limit: u128,
        is_above_dust: bool,
    }

    #[abi(embed_v0)]
    pub impl AssetRouterImpl of IAssetRouter<ContractState> {
        fn mint(
            ref self: ContractState,
            to_chain: u256,
            recipient: ContractAddress,
            amount: u256,
            tx_id: u256,
            vout: u32,
            proof: Span<Signature>,
        ) {
            assert(
                to_chain == get_tx_info().unbox().chain_id.into() + LOMBARD_STARKNET_IDENTIFIER,
                errors::WRONG_CHAIN_ID,
            );
            assert(recipient.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
            assert(amount.is_non_zero(), errors::INVALID_ZERO_AMOUNT);
            self._validate_and_mint(:amount, :to_chain, :recipient, :tx_id, :vout, :proof);
        }

        /// Burns LBTC to initiate withdrawal of BTC to provided `scriptPubkey` with `amount`.
        ///
        /// Arguments:
        /// scriptPubkey for output.
        /// Amount of LBTC to burn.
        fn redeem(ref self: ContractState, script_pub_key: ByteArray, amount: u256) {
            assert(self.is_withdrawals_enabled.read(), errors::WITHDRAWALS_DISABLED);

            let fee = self.burn_commission.read();

            let FeeDustInfo {
                amount_after_fee, is_above_fee, dust_limit, is_above_dust,
            } = self._calculate_fee_and_dust_limit(script_pub_key: @script_pub_key, :amount, :fee);

            assert_with_byte_array(is_above_fee, errors::amount_less_than_commission(:fee));
            assert_with_byte_array(is_above_dust, errors::amount_below_dust_limit(:dust_limit));

            let caller_address = get_caller_address();
            let token_dispatcher = self.lbtc_token.read();

            // Validate there are enough locked btc on the other side
            let locked_amount = self.btc_locked_amount.read();
            assert(locked_amount >= amount_after_fee, errors::REDEEM_LIMIT_EXCEEDED);
            self.btc_locked_amount.write(locked_amount - amount_after_fee);

            // This equivalent to burning `amount_after_fee`, and transfer fee to treasury.
            token_dispatcher.permissioned_burn(account: caller_address, amount: amount);
            token_dispatcher.permissioned_mint(account: self.get_treasury(), amount: fee.into());

            self
                .emit(
                    events::UnstakeRequest {
                        from_address: caller_address, script_pub_key, amount_after_fee,
                    },
                );
        }

        /// ONLY APP_GOVERNOR FUNCTIONS ///

        fn change_bascule(ref self: ContractState, new_bascule: ContractAddress) {
            self.roles.only_app_governor();
            self._set_bascule_address(:new_bascule);
        }

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
        /// Change the dust fee rate (in satoshis per 1000 bytes) used for dust limit calculations.
        /// Only the app governor can call this function.
        /// The new rate must greater than 0.
        fn change_dust_fee_rate(ref self: ContractState, new_rate: u128) {
            self.roles.only_app_governor();
            self._change_dust_fee_rate(:new_rate);
        }

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

        /// Calculates the unstakeable amount after burn commission and checks against the dust
        /// limit.
        ///
        /// Returns:
        /// - `amount_after_fee`: The amount that will be unstaked.
        /// - `is_above_dust`: True if `amount_after_fee` >= dust limit.
        ///
        /// Intended for frontends to validate unstake requests before submission.
        fn calculate_unstake_request_amount(
            self: @ContractState, script_pub_key: ByteArray, amount: u256,
        ) -> (u256, bool) {
            let fee = self.burn_commission.read();
            let FeeDustInfo {
                amount_after_fee, is_above_fee: _, dust_limit: _, is_above_dust,
            } = self._calculate_fee_and_dust_limit(script_pub_key: @script_pub_key, :amount, :fee);

            (amount_after_fee, is_above_dust)
        }

        /// Gets the current dust fee rate (in satoshis per 1000 bytes).
        fn get_dust_fee_rate(self: @ContractState) -> u128 {
            self.dust_fee_rate.read()
        }

        fn is_payload_used(self: @ContractState, payload_hash: u256) -> bool {
            self.used_payloads.read(payload_hash)
        }

        fn is_withdrawals_enabled(self: @ContractState) -> bool {
            self.is_withdrawals_enabled.read()
        }
    }


    #[generate_trait]
    impl PrivateImpl of PrivateAssetRouter {
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
            assert(new_burn_commission <= MAX_FEE, errors::INVALID_BURN_COMMISSION);
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
            let old_bascule = self.get_bascule();
            self.bascule.write(IBasculeDispatcher { contract_address: new_bascule });
            self.emit(events::BasculeChanged { old_bascule, new_bascule });
        }

        fn _change_dust_fee_rate(ref self: ContractState, new_rate: u128) {
            assert(new_rate.is_non_zero(), errors::INVALID_ZERO_DUST_FEE_RATE);

            let old_rate = self.dust_fee_rate.read();
            self.dust_fee_rate.write(new_rate);

            self.emit(events::DustFeeRateChanged { old_rate, new_rate });
        }

        fn _validate_and_mint(
            ref self: ContractState,
            amount: u256,
            to_chain: u256,
            recipient: ContractAddress,
            tx_id: u256,
            vout: u32,
            proof: Span<Signature>,
        ) {
            let payload: ByteArray = build_deposit_payload_with_selector(
                :to_chain, :recipient, :amount, :tx_id, :vout,
            );

            let payload_hash: u256 = u256_from_u32_array(compute_sha256_byte_array(arr: @payload));
            assert(!self.is_payload_used(:payload_hash), errors::PAYLOAD_ALREADY_USED);
            self.used_payloads.write(payload_hash, true);
            let consortium = self.consortium.read();
            consortium.check_proof(msg_hash: payload_hash, :proof);

            // Confirm deposit against Bascule
            self._confirm_deposit(:to_chain, :recipient, :amount, :tx_id, :vout);

            // Mint `amount` to `recipient`.
            self.btc_locked_amount.add_and_write(amount);
            let lbtc_token = self.lbtc_token.read();
            lbtc_token.permissioned_mint(account: recipient, amount: amount);

            self.emit(events::MintProofConsumed { recipient, payload_hash, payload });
        }

        /// Calculates the post-fee amount and checks if it's above the dust limit.
        ///
        /// Returns:
        /// - `amount_after_fee`: The amount after fee deduction.
        /// - `is_amount_valid`: True if `amount > fee`.
        /// - `dust_limit`: The dust threshold for the script.
        /// - `is_above_dust`: True if `amount_after_fee > dust_limit`.
        ///
        fn _calculate_fee_and_dust_limit(
            self: @ContractState, script_pub_key: @ByteArray, amount: u256, fee: u64,
        ) -> FeeDustInfo {
            let output_type = get_output_type(:script_pub_key);
            assert(output_type != OutputType::UNSUPPORTED, errors::SCRIPT_PUB_KEY_UNSUPPORTED);

            if amount <= fee.into() {
                return FeeDustInfo {
                    amount_after_fee: 0, is_above_fee: false, dust_limit: 0, is_above_dust: false,
                };
            }

            let amount_after_fee = amount - fee.into();
            let dust_fee_rate = self.dust_fee_rate.read();
            let dust_limit = get_dust_limit_for_output(
                :output_type, :script_pub_key, :dust_fee_rate,
            );
            let is_above_dust = amount_after_fee > dust_limit.into();

            FeeDustInfo { amount_after_fee, is_above_fee: true, dust_limit, is_above_dust }
        }

        /// Checks that the deposit was validated by the Bascule drawbridge.
        /// @param deposit_id The unique ID of the deposit.
        /// @param amount The withdrawal amount.
        fn _confirm_deposit(
            self: @ContractState,
            to_chain: u256,
            recipient: ContractAddress,
            amount: u256,
            tx_id: u256,
            vout: u32,
        ) {
            let bascule = self.bascule.read();
            if bascule.contract_address.is_non_zero() {
                bascule
                    .validate_withdrawal(
                        :to_chain, :recipient, withdrawal_amount: amount, :tx_id, :vout,
                    );
            }
        }
    }
}


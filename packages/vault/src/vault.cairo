#[starknet::contract]
pub mod vault {
    use core::num::traits::{Pow, Zero};
    use erc4626::erc4626::ERC4626Component;
    use erc4626::erc4626::ERC4626Component::{ComponentState as ERC4626ComponentState, InternalImpl};
    use erc4626::interface::{IERC4626, IERC4626Dispatcher, IERC4626DispatcherTrait};
    use lbtc_manual_strategy::interface::{
        IManualStrategyDispatcher, IManualStrategyDispatcherTrait,
    };
    use lbtc_vault::errors::{
        ILLEGAL_PERFORMANCE_FEE_LEN, INVALID_FEE_AMOUNT, INVALID_LOWER_BOUND, INVALID_UPPER_BOUND,
        INVALID_ZERO_ADDRESS, INVALID_ZERO_DEPOSIT_LIMIT, SHARES_BELOW_DUST,
        WITHDRAWALS_ALREADY_DISABLED, WITHDRAWALS_ALREADY_ENABLED, WITHDRAWALS_PAUSED,
    };
    use lbtc_vault::events::{DepositLimitSet, FeeRecipientUpdated, WithdrawalPausedToggled};
    use lbtc_vault::interface::IVault;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::security::ReentrancyGuardComponent;
    use openzeppelin::security::ReentrancyGuardComponent::InternalTrait as ReentrancyGuardInternal;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::token::erc20::ERC20Component::InternalTrait;
    use openzeppelin::token::erc20::interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::utils::math::{Rounding, u256_mul_div};
    use starknet::storage::{
        MutableVecTrait, StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::pausable::interface::IPausable;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::constants::{DAY, HOUR};
    use starkware_utils::time::time::{Time, Timestamp};

    const INIT_HIGH_WATER_MARK: u256 = 10_u256.pow(ImmutableConfigImpl::UNDERLYING_DECIMALS.into());
    const MAX_BASIS_POINTS: u64 = 10_000;
    const AVERAGE_YEAR: u64 = 365 * DAY + 6 * HOUR;
    const DUST: u256 = 100_000_000;
    const SHARE_UNIT_BASIS: u256 = 10_u256
        .pow(
            (ImmutableConfigImpl::DECIMALS_OFFSET + ImmutableConfigImpl::UNDERLYING_DECIMALS)
                .into(),
        );

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: ERC4626Component, storage: erc4626, event: ERC4626Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(
        path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent,
    );
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // External

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    impl ERC4626 = ERC4626Component::ERC4626Impl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20 = ERC20Component::ERC20Impl<ContractState>;

    #[storage]
    struct Storage {
        // --- Components ---
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        erc4626: ERC4626Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        pub replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        // --- Vault ---
        strategy_address: ContractAddress,
        deposit_limit: u256,
        fees_updated_at: Timestamp,
        fee_recipient: ContractAddress,
        withdrawals_paused: bool,
        // Stores the maximum per-share value, denominated in asset units.
        high_water_mark: u256,
        // Fees:
        deposit_fee: u64,
        withdrawal_fee: u64,
        protocol_fee: u64,
        performance_fee: Vec<(u256, u256, u64)>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        ERC4626Event: ERC4626Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        DepositLimitSet: DepositLimitSet,
        FeeRecipientUpdated: FeeRecipientUpdated,
        WithdrawalPausedToggled: WithdrawalPausedToggled,
    }


    impl ImmutableConfigImpl of ERC4626Component::ImmutableConfig {
        const UNDERLYING_DECIMALS: u8 = 8;
        const DECIMALS_OFFSET: u8 = 9;
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        token_address: ContractAddress,
        strategy_address: ContractAddress,
        deposit_limit: u256,
        fee_recipient: ContractAddress,
        deposit_fee: u64,
        withdrawal_fee: u64,
        protocol_fee: u64,
        performance_fee: Span<(u256, u256, u64)>,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self.erc4626.initializer(asset_address: token_address);

        assert(strategy_address.is_non_zero(), INVALID_ZERO_ADDRESS);
        self.strategy_address.write(strategy_address);

        assert(deposit_limit.is_non_zero(), INVALID_ZERO_DEPOSIT_LIMIT);
        self.deposit_limit.write(deposit_limit);

        assert(fee_recipient.is_non_zero(), INVALID_ZERO_ADDRESS);
        self.fee_recipient.write(fee_recipient);

        self.withdrawals_paused.write(false);
        self.high_water_mark.write(INIT_HIGH_WATER_MARK);

        self._set_fees(:deposit_fee, :withdrawal_fee, :protocol_fee, :performance_fee);
    }

    impl FeeConfigTraitImpl of ERC4626Component::FeeConfigTrait<ContractState> {
        /// Adjusts deposits within `preview_deposit` to account for entry fees.
        /// Entry fees should be transferred in the `after_deposit` hook.
        fn deduct_deposit_fee(
            self: @ERC4626ComponentState<ContractState>, gross_value: u256,
        ) -> u256 {
            let vault = self.get_contract();
            if get_caller_address() == vault.get_fee_recipient() {
                return gross_value;
            }
            let fee_value = u256_mul_div(
                x: gross_value,
                y: vault.get_deposit_fee().into(),
                denominator: MAX_BASIS_POINTS.into(),
                rounding: Rounding::Ceil,
            );
            gross_value - fee_value
        }

        /// Adjusts mints within `preview_mint` to account for entry fees.
        /// Entry fees should be transferred in the `after_deposit` hook.
        fn add_mint_fee(self: @ERC4626ComponentState<ContractState>, net_value: u256) -> u256 {
            let vault = self.get_contract();
            if get_caller_address() == vault.get_fee_recipient() {
                return net_value;
            }
            let gross_value = u256_mul_div(
                x: net_value,
                y: MAX_BASIS_POINTS.into(),
                denominator: (MAX_BASIS_POINTS - vault.get_deposit_fee()).into(),
                rounding: Rounding::Ceil,
            );
            gross_value
        }

        /// Adjusts withdraws within `preview_withdraw` to account for exit fees.
        /// Exit fees should be transferred in the `before_withdraw` hook.
        fn add_withdraw_fee(self: @ERC4626ComponentState<ContractState>, net_value: u256) -> u256 {
            let vault = self.get_contract();
            if get_caller_address() == vault.get_fee_recipient() {
                return net_value;
            }
            let gross_value = u256_mul_div(
                x: net_value,
                y: MAX_BASIS_POINTS.into(),
                denominator: (MAX_BASIS_POINTS - vault.get_withdrawal_fee()).into(),
                rounding: Rounding::Ceil,
            );
            gross_value
        }

        /// Adjusts redeems within `preview_redeem` to account for exit fees.
        /// Exit fees should be transferred in the `before_withdraw` hook.
        fn deduct_redeem_fee(
            self: @ERC4626ComponentState<ContractState>, gross_values: u256,
        ) -> u256 {
            let vault = self.get_contract();
            if get_caller_address() == vault.get_fee_recipient() {
                return gross_values;
            }
            let net_value = u256_mul_div(
                x: gross_values,
                y: (MAX_BASIS_POINTS - vault.get_withdrawal_fee()).into(),
                denominator: MAX_BASIS_POINTS.into(),
                rounding: Rounding::Floor,
            );
            net_value
        }
    }

    impl LimitConfigTraitImpl of ERC4626Component::LimitConfigTrait<ContractState> {
        fn deposit_limit(
            self: @ERC4626ComponentState<ContractState>, receiver: ContractAddress,
        ) -> Option<u256> {
            assert(receiver.is_non_zero(), INVALID_ZERO_ADDRESS);

            let vault = self.get_contract();
            if vault.pausable.is_paused() {
                return Option::Some(0);
            }

            let deposit_limit = vault.get_deposit_limit();
            let total_assets = self.total_assets();
            if total_assets >= deposit_limit {
                return Option::Some(0);
            }

            Option::Some(deposit_limit - total_assets)
        }

        /// The max mint allowed.
        fn mint_limit(
            self: @ERC4626ComponentState<ContractState>, receiver: ContractAddress,
        ) -> Option<u256> {
            let gross_shares = self
                .deposit_limit(receiver)
                .map(
                    |asset_limit| self
                        ._convert_to_shares(assets: asset_limit, rounding: Rounding::Floor),
                );

            let net_shares = self.deduct_deposit_fee(gross_value: gross_shares.unwrap_or_default());
            Option::Some(net_shares)
        }

        /// The max withdraw allowed.
        fn withdraw_limit(
            self: @ERC4626ComponentState<ContractState>, owner: ContractAddress,
        ) -> Option<u256> {
            let vault = self.get_contract();
            // Get the raw max withdrawal amount for the owner.
            let shares = vault.erc20.balance_of(owner);
            let total_assets = vault.erc4626.total_assets();

            let mut raw_max_withdraw = self._convert_to_assets(:shares, rounding: Rounding::Floor);

            if owner == vault.get_fee_recipient() {
                // If the owner is the fee recipient, no need to apply fee.
                return Option::Some(raw_max_withdraw);
            }

            // Calculate pending fees.
            let pending_fees = vault.accrued_protocol_fee() + vault.accrued_performance_fee();
            raw_max_withdraw =
                u256_mul_div(
                    x: raw_max_withdraw,
                    y: total_assets,
                    denominator: total_assets + pending_fees,
                    rounding: Rounding::Floor,
                );

            let max_withdraw = u256_mul_div(
                x: raw_max_withdraw,
                y: (MAX_BASIS_POINTS - vault.get_withdrawal_fee()).into(),
                denominator: MAX_BASIS_POINTS.into(),
                rounding: Rounding::Floor,
            );

            Option::Some(max_withdraw)
        }
    }

    impl ERC4626HooksTraitImpl of ERC4626Component::ERC4626HooksTrait<ContractState> {
        /// Hooks into `InternalImpl::_withdraw`.
        /// Executes logic before burning shares and transferring assets.
        /// It mints the fee shares to the fee recipient, and withdraw the assets from the strategy.
        fn before_withdraw(
            ref self: ERC4626ComponentState<ContractState>,
            assets: u256,
            shares: u256,
            fee_in_shares: u256,
        ) {
            let mut vault = self.get_contract_mut();
            assert(!vault.withdrawals_paused.read(), WITHDRAWALS_PAUSED);
            assert(shares > DUST, SHARES_BELOW_DUST);

            let fee_recipient_address = vault.get_fee_recipient();
            if get_caller_address() != fee_recipient_address && fee_in_shares.is_non_zero() {
                vault.erc20.mint(recipient: fee_recipient_address, amount: fee_in_shares);
            }

            let this = get_contract_address();
            IERC4626Dispatcher { contract_address: vault.strategy_address.read() }
                .withdraw(:assets, receiver: this, owner: this);
        }
        /// Hooks into `InternalImpl::_deposit`.
        /// Executes logic after transferring assets and minting shares.
        /// It mints the fee shares to the fee recipient, and deposits the assets to the strategy.
        fn after_deposit(
            ref self: ERC4626ComponentState<ContractState>,
            assets: u256,
            shares: u256,
            fee_in_shares: u256,
        ) {
            let mut vault = self.get_contract_mut();

            // Check DUST limit.
            assert(shares > DUST, SHARES_BELOW_DUST);

            let fee_recipient = vault.get_fee_recipient();
            if get_caller_address() != fee_recipient && fee_in_shares.is_non_zero() {
                vault.erc20.mint(recipient: fee_recipient, amount: fee_in_shares);
            }

            let strategy_address = vault.strategy_address.read();
            IERC20Dispatcher { contract_address: self.asset() }
                .approve(spender: strategy_address, amount: assets);
            IERC4626Dispatcher { contract_address: strategy_address }
                .deposit(:assets, receiver: get_contract_address());
        }
    }

    impl ERC20HooksTraitImpl of ERC20Component::ERC20HooksTrait<ContractState>;

    impl TotalAssetCalcTraitImpl of ERC4626Component::TotalAssetCalcTrait<ContractState> {
        fn calculate_total_assets(self: @ERC4626ComponentState<ContractState>) -> u256 {
            let vault = self.get_contract();

            let strategy_address = vault.strategy_address.read();
            let strategy_asset_dispatcher = IERC4626Dispatcher {
                contract_address: strategy_address,
            };
            strategy_asset_dispatcher.total_assets()
        }
    }

    #[abi(embed_v0)]
    pub impl VaultImpl of IVault<ContractState> {
        fn enable_withdrawals(ref self: ContractState) {
            self.roles.only_app_governor();
            assert(self.withdrawals_paused.read(), WITHDRAWALS_ALREADY_ENABLED);

            self.withdrawals_paused.write(false);
            self.emit(WithdrawalPausedToggled { past_value: true, new_value: false });
        }

        fn disable_withdrawals(ref self: ContractState) {
            self.roles.only_app_governor();
            assert(!self.withdrawals_paused.read(), WITHDRAWALS_ALREADY_DISABLED);

            self.withdrawals_paused.write(true);
            self.emit(WithdrawalPausedToggled { past_value: false, new_value: true });
        }

        fn set_fees(
            ref self: ContractState,
            deposit_fee: u64,
            withdrawal_fee: u64,
            protocol_fee: u64,
            performance_fee: Span<(u256, u256, u64)>,
        ) {
            self._take_fees();
            self.roles.only_app_governor();
            self._set_fees(:deposit_fee, :withdrawal_fee, :protocol_fee, :performance_fee);
        }

        fn set_fee_recipient(ref self: ContractState, new_recipient: ContractAddress) {
            self.roles.only_app_governor();
            assert(new_recipient.is_non_zero(), INVALID_ZERO_ADDRESS);

            let old_recipient = self.fee_recipient.read();
            self.fee_recipient.write(new_recipient);

            self.emit(FeeRecipientUpdated { old_recipient, new_recipient });
        }

        fn set_deposit_limit(ref self: ContractState, new_limit: u256) {
            self.roles.only_app_governor();
            assert(new_limit.is_non_zero(), INVALID_ZERO_DEPOSIT_LIMIT);
            self.deposit_limit.write(new_limit);

            self.emit(DepositLimitSet { limit: new_limit });
        }

        fn force_pause(ref self: ContractState) {
            self.pausable.pause();
        }

        fn get_fee_recipient(self: @ContractState) -> ContractAddress {
            self.fee_recipient.read()
        }

        fn get_deposit_fee(self: @ContractState) -> u64 {
            self.deposit_fee.read()
        }

        fn get_withdrawal_fee(self: @ContractState) -> u64 {
            self.withdrawal_fee.read()
        }

        fn get_protocol_fee(self: @ContractState) -> u64 {
            self.protocol_fee.read()
        }

        fn get_deposit_limit(self: @ContractState) -> u256 {
            self.deposit_limit.read()
        }

        fn get_available_assets_for_withdrawal(self: @ContractState) -> u256 {
            let strategy_dispatcher = IManualStrategyDispatcher {
                contract_address: self.strategy_address.read(),
            };
            strategy_dispatcher.get_available_assets_for_withdrawal()
        }

        fn accrued_protocol_fee(self: @ContractState) -> u256 {
            let time_delta: u64 = Time::now().sub(self.fees_updated_at.read()).into();
            // Calculate the fee based on time elapsed from last updated fee, and total
            // assets.
            u256_mul_div(
                x: self.get_protocol_fee().into() * self.erc4626.total_assets(),
                y: time_delta.into(),
                denominator: AVERAGE_YEAR.into() * MAX_BASIS_POINTS.into(),
                rounding: Rounding::Floor,
            )
        }

        fn accrued_performance_fee(self: @ContractState) -> u256 {
            let asset_per_share_unit = self
                .erc4626
                ._convert_to_assets(shares: SHARE_UNIT_BASIS, rounding: Rounding::Floor);
            let high_water_mark = self.high_water_mark.read();

            if self.performance_fee.len().is_non_zero() && asset_per_share_unit > high_water_mark {
                let diff = u256_mul_div(
                    x: asset_per_share_unit,
                    y: MAX_BASIS_POINTS.into(),
                    denominator: high_water_mark,
                    rounding: Rounding::Floor,
                )
                    - MAX_BASIS_POINTS.into();

                let total_assets = self.erc4626.total_assets();

                for i in 0..self.performance_fee.len() {
                    let tier = self
                        .performance_fee
                        .get(i)
                        .expect(ILLEGAL_PERFORMANCE_FEE_LEN)
                        .read();
                    let (lower_bound, upper_bound, fee) = tier;
                    if lower_bound <= diff && diff <= upper_bound {
                        return u256_mul_div(
                            x: (asset_per_share_unit - high_water_mark) * total_assets,
                            y: fee.into(),
                            denominator: MAX_BASIS_POINTS.into()
                                * 10_u256.pow(ImmutableConfigImpl::UNDERLYING_DECIMALS.into()),
                            rounding: Rounding::Floor,
                        );
                    }
                }
            }
            Default::default()
        }
    }

    #[abi(embed_v0)]
    pub impl VaultPauseImpl of IPausable<ContractState> {
        fn pause(ref self: ContractState) {
            self._take_fees();
            self.pausable.pause();
        }

        fn unpause(ref self: ContractState) {
            self.pausable.unpause();
            self.fees_updated_at.write(Time::now());
        }

        fn is_paused(self: @ContractState) -> bool {
            self.pausable.is_paused()
        }
    }

    #[abi(embed_v0)]
    pub impl VaultERC4626Impl of IERC4626<ContractState> {
        fn deposit(ref self: ContractState, assets: u256, receiver: ContractAddress) -> u256 {
            self.pausable.assert_not_paused();
            self.reentrancy_guard.start();
            self._take_fees();
            if (self.erc20.total_supply().is_zero()) {
                self.fees_updated_at.write(Time::now());
            }

            let shares = self.erc4626.deposit(:assets, :receiver);

            self.reentrancy_guard.end();
            shares
        }
        fn mint(ref self: ContractState, shares: u256, receiver: ContractAddress) -> u256 {
            self.pausable.assert_not_paused();
            self.reentrancy_guard.start();
            self._take_fees();
            if (self.erc20.total_supply().is_zero()) {
                self.fees_updated_at.write(Time::now());
            }

            let assets = self.erc4626.mint(:shares, :receiver);

            self.reentrancy_guard.end();
            assets
        }
        fn withdraw(
            ref self: ContractState,
            assets: u256,
            receiver: ContractAddress,
            owner: ContractAddress,
        ) -> u256 {
            self.pausable.assert_not_paused();
            self.reentrancy_guard.start();
            self._take_fees();

            let shares = self.erc4626.withdraw(:assets, :receiver, :owner);

            self.reentrancy_guard.end();
            shares
        }
        fn redeem(
            ref self: ContractState,
            shares: u256,
            receiver: ContractAddress,
            owner: ContractAddress,
        ) -> u256 {
            self.pausable.assert_not_paused();
            self.reentrancy_guard.start();
            self._take_fees();

            let assets = self.erc4626.redeem(:shares, :receiver, :owner);

            self.reentrancy_guard.end();
            assets
        }
        fn max_deposit(self: @ContractState, receiver: ContractAddress) -> u256 {
            self.erc4626.max_deposit(:receiver)
        }
        fn max_mint(self: @ContractState, receiver: ContractAddress) -> u256 {
            self.erc4626.max_mint(:receiver)
        }
        fn max_withdraw(self: @ContractState, owner: ContractAddress) -> u256 {
            self.erc4626.max_withdraw(:owner)
        }
        fn max_redeem(self: @ContractState, owner: ContractAddress) -> u256 {
            self.erc4626.max_redeem(:owner)
        }
        fn preview_deposit(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.preview_deposit(:assets)
        }
        fn preview_mint(self: @ContractState, shares: u256) -> u256 {
            self.erc4626.preview_mint(:shares)
        }
        fn preview_withdraw(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.preview_withdraw(:assets)
        }
        fn preview_redeem(self: @ContractState, shares: u256) -> u256 {
            self.erc4626.preview_redeem(:shares)
        }
        fn asset(self: @ContractState) -> ContractAddress {
            self.erc4626.asset()
        }
        fn total_assets(self: @ContractState) -> u256 {
            self.erc4626.total_assets()
        }
        fn convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            self.erc4626.convert_to_assets(:shares)
        }
        fn convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.convert_to_shares(:assets)
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateVault {
        fn _set_fees(
            ref self: ContractState,
            deposit_fee: u64,
            withdrawal_fee: u64,
            protocol_fee: u64,
            performance_fee: Span<(u256, u256, u64)>,
        ) {
            assert(
                deposit_fee <= MAX_BASIS_POINTS
                    && withdrawal_fee <= MAX_BASIS_POINTS
                    && protocol_fee <= MAX_BASIS_POINTS,
                INVALID_FEE_AMOUNT,
            );
            self.deposit_fee.write(deposit_fee);
            self.withdrawal_fee.write(withdrawal_fee);
            self.protocol_fee.write(protocol_fee);
            // Clear the performance fee vector
            while self.performance_fee.pop() != Option::None {}
            let mut prev_fee = 0_u64;
            let mut prev_upper_bound = 0_u256;
            for tier in performance_fee {
                let (lower_bound, upper_bound, fee) = *tier;
                // First bound starts from 0.
                if prev_upper_bound.is_zero() {
                    assert(lower_bound.is_zero(), INVALID_LOWER_BOUND);
                } else {
                    assert(prev_upper_bound == lower_bound + 1, INVALID_LOWER_BOUND);
                }
                assert(lower_bound < upper_bound, INVALID_UPPER_BOUND);
                assert(prev_fee < fee && fee <= MAX_BASIS_POINTS, INVALID_FEE_AMOUNT);
                self.performance_fee.push(*tier);

                prev_fee = fee;
                prev_upper_bound = upper_bound;
            }
            assert(prev_upper_bound == MAX_BASIS_POINTS.into(), INVALID_UPPER_BOUND);
            self.fees_updated_at.write(Time::now());
        }

        fn _take_fees(ref self: ContractState) {
            if self.pausable.is_paused() {
                return;
            }

            let total_fee_in_assets = self.accrued_protocol_fee() + self.accrued_performance_fee();
            let asset_per_share_unit = self
                .erc4626
                ._convert_to_assets(shares: SHARE_UNIT_BASIS, rounding: Rounding::Floor);
            let total_assets = self.erc4626.total_assets();
            assert(total_fee_in_assets < total_assets, INVALID_FEE_AMOUNT);

            // Update high water mark if current per-share asset value exceeds the previous.
            let high_water_mark = self.high_water_mark.read();
            if asset_per_share_unit > high_water_mark {
                self.high_water_mark.write(asset_per_share_unit);
            }

            if total_fee_in_assets.is_non_zero() && total_assets.is_non_zero() {
                let supply = self.erc20.total_supply();
                let fee_in_shares = u256_mul_div(
                    x: total_fee_in_assets,
                    y: supply + 10_u256.pow(Immutable::DECIMALS_OFFSET.into()),
                    denominator: total_assets - total_fee_in_assets,
                    rounding: Rounding::Floor,
                );

                // Take fees by diluting the users.
                self.erc20.mint(recipient: self.fee_recipient.read(), amount: fee_in_shares);
                self.fees_updated_at.write(Time::now());
            }
        }
    }
}


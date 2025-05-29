#[starknet::contract]
pub mod vault {
    use core::num::traits::{Pow, Zero};
    use lbtc_manual_strategy::interface::{
        IManualStrategyDispatcher, IManualStrategyDispatcherTrait,
    };
    use lbtc_vault::errors::{
        INVALID_FEE_AMOUNT, INVALID_LOWER_BOUND, INVALID_UPPER_BOUND, INVALID_ZERO_ADDRESS,
        INVALID_ZERO_DEPOSIT_LIMIT, SHARES_BELOW_DUST, WITHDRAWALS_ALREADY_DISABLED,
        WITHDRAWALS_ALREADY_ENABLED, WITHDRAWALS_PAUSED,
    };
    use lbtc_vault::events::{DepositLimitSet, FeeRecipientUpdated, WithdrawalPausedToggled};
    use lbtc_vault::interface::IVault;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::security::ReentrancyGuardComponent;
    use openzeppelin::security::ReentrancyGuardComponent::InternalTrait as ReentrancyGuardInternal;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::token::erc20::ERC20Component::InternalTrait;
    use openzeppelin::token::erc20::extensions::erc4626::ERC4626Component::{
        ComponentState as ERC4626ComponentState, InternalImpl,
    };
    use openzeppelin::token::erc20::extensions::erc4626::interface::IERC4626;
    use openzeppelin::token::erc20::extensions::erc4626::{DefaultConfig, ERC4626Component};
    use openzeppelin::token::erc20::interface::IERC20;
    use openzeppelin::utils::math::{Rounding, u256_mul_div};
    use starknet::storage::{
        MutableVecTrait, StoragePointerReadAccess, StoragePointerWriteAccess, Vec,
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
    use starkware_utils::types::time::time::{Time, Timestamp};

    const INIT_HIGH_WATER_MARK: u256 = 1_000_000_000;
    const MAX_BASIS_POINTS: u64 = 10_000;
    // TODO(Tomer-StarkWare): move this to utils.
    const YEAR: u64 = 365 * DAY + 6 * HOUR;
    const DUST: u256 = 100_000_000;
    const FEE_PERCENTAGE: u256 = 10_000;

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

    #[abi(embed_v0)]
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
        strategy_dispatcher: IManualStrategyDispatcher,
        deposit_limit: u256,
        fees_updated_at: Timestamp,
        fee_recipient: ContractAddress,
        // TODO(Mohammad): consider using pause component.
        withdrawals_paused: bool,
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
        self
            .strategy_dispatcher
            .write(IManualStrategyDispatcher { contract_address: strategy_address });

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
        fn adjust_deposit(self: @ERC4626ComponentState<ContractState>, assets: u256) -> u256 {
            let vault = self.get_contract();
            if get_caller_address() == vault.get_fee_recipient() {
                return assets;
            }
            let fee_assets = u256_mul_div(
                assets, vault.get_deposit_fee().into(), MAX_BASIS_POINTS.into(), Rounding::Ceil,
            );
            assets - fee_assets
        }

        /// Adjusts mints within `preview_mint` to account for entry fees.
        /// Entry fees should be transferred in the `after_deposit` hook.
        fn adjust_mint(self: @ERC4626ComponentState<ContractState>, assets: u256) -> u256 {
            let vault = self.get_contract();
            u256_mul_div(
                assets,
                MAX_BASIS_POINTS.into(),
                (MAX_BASIS_POINTS - vault.get_deposit_fee()).into(),
                Rounding::Ceil,
            )
        }

        /// Adjusts withdraws within `preview_withdraw` to account for exit fees.
        /// Exit fees should be transferred in the `before_withdraw` hook.
        fn adjust_withdraw(self: @ERC4626ComponentState<ContractState>, assets: u256) -> u256 {
            let vault = self.get_contract();
            if get_caller_address() == vault.get_fee_recipient() {
                return assets;
            }
            u256_mul_div(
                x: assets,
                y: MAX_BASIS_POINTS.into(),
                denominator: (MAX_BASIS_POINTS - vault.get_withdrawal_fee()).into(),
                rounding: Rounding::Ceil,
            )
        }

        /// Adjusts redeems within `preview_redeem` to account for exit fees.
        /// Exit fees should be transferred in the `before_withdraw` hook.
        fn adjust_redeem(self: @ERC4626ComponentState<ContractState>, assets: u256) -> u256 {
            let vault = self.get_contract();
            if get_caller_address() == vault.get_fee_recipient() {
                return assets;
            }
            u256_mul_div(
                x: assets,
                y: (MAX_BASIS_POINTS - vault.get_withdrawal_fee()).into(),
                denominator: MAX_BASIS_POINTS.into(),
                rounding: Rounding::Floor,
            )
        }
    }

    impl LimitConfigTraitImpl of ERC4626Component::LimitConfigTrait<ContractState> {
        fn deposit_limit(
            self: @ERC4626ComponentState<ContractState>, receiver: ContractAddress,
        ) -> Option<u256> {
            assert(receiver.is_non_zero(), INVALID_ZERO_ADDRESS);

            let vault = self.get_contract();
            let deposit_limit = vault.get_deposit_limit();
            let total_assets = self.total_assets();

            Option::Some(deposit_limit - total_assets)
        }

        /// The max mint allowed.
        /// Defaults (`Option::None`) to 2 ** 256 - 1.
        fn mint_limit(
            self: @ERC4626ComponentState<ContractState>, receiver: ContractAddress,
        ) -> Option<u256> {
            let vault = self.get_contract();

            if vault.is_paused() {
                return Option::Some(0);
            }

            let total_assets = self.total_assets();
            let deposit_limit = vault.get_deposit_limit();
            if total_assets >= deposit_limit {
                return Option::Some(0);
            }

            Option::Some(
                self
                    ._convert_to_shares(
                        assets: deposit_limit - total_assets, rounding: Rounding::Ceil,
                    ),
            )
        }

        /// The max withdraw allowed.
        /// Defaults (`Option::None`) to the full asset balance of `owner` converted from shares.
        fn withdraw_limit(
            self: @ERC4626ComponentState<ContractState>, owner: ContractAddress,
        ) -> Option<u256> {
            let vault = self.get_contract();
            // Get the raw max withdrawal amount for the owner.
            let shares = vault.erc20.balance_of(owner);
            let raw_max_withdraw = self._convert_to_assets(:shares, rounding: Rounding::Floor);

            // Calculate pending fees.
            let pending_fees = vault.accrued_protocol_fee();

            // Return max withdraw minus pending fees.
            let max_withdraw = u256_mul_div(
                x: raw_max_withdraw,
                y: (MAX_BASIS_POINTS - vault.get_withdrawal_fee()).into(),
                denominator: MAX_BASIS_POINTS.into(),
                rounding: Rounding::Floor,
            );

            Option::Some(max_withdraw - pending_fees)
        }
    }

    impl ERC4626HooksTraitImpl of ERC4626Component::ERC4626HooksTrait<ContractState> {
        /// Hooks into `InternalImpl::_withdraw`.
        /// Executes logic before burning shares and transferring assets.
        fn before_withdraw(
            ref self: ERC4626ComponentState<ContractState>, assets: u256, shares: u256,
        ) {
            let mut vault = self.get_contract_mut();
            assert(!vault.withdrawals_paused.read(), WITHDRAWALS_PAUSED);
            assert(shares > DUST, SHARES_BELOW_DUST);

            let fee_recipient_address = vault.get_fee_recipient();
            if get_caller_address() != fee_recipient_address {
                let fee_shares = shares
                    - self._convert_to_shares(:assets, rounding: Rounding::Floor);
                if fee_shares > 0 {
                    vault.erc20.mint(recipient: fee_recipient_address, amount: fee_shares);
                }
            }
        }
        /// Hooks into `InternalImpl::_deposit`.
        /// Executes logic after transferring assets and minting shares.
        fn after_deposit(
            ref self: ERC4626ComponentState<ContractState>, assets: u256, shares: u256,
        ) {
            let mut vault = self.get_contract_mut();

            // Check DUST limit.
            assert(shares > DUST, SHARES_BELOW_DUST);

            let fee_recipient = vault.get_fee_recipient();
            // Calculate again the fee in shares.
            if get_caller_address() != fee_recipient {
                // Calculate the fee in shares.
                let fee_assets = u256_mul_div(
                    x: assets,
                    y: vault.get_deposit_fee().into(),
                    denominator: MAX_BASIS_POINTS.into(),
                    rounding: Rounding::Ceil,
                );
                let fee_shares = self
                    ._convert_to_shares(assets: fee_assets, rounding: Rounding::Ceil);

                if fee_shares.is_non_zero() {
                    vault.erc20.mint(recipient: fee_recipient, amount: fee_shares);
                }
            }
            // TODO(Mohammad): call `strategy_dispatcher.deposit`.
        }
    }

    impl ERC20HooksTraitImpl of ERC20Component::ERC20HooksTrait<ContractState>;

    #[abi(embed_v0)]
    pub impl VaultImpl of IVault<ContractState> {
        fn enable_withdrawals(ref self: ContractState) {
            self.roles.only_app_governor();
            assert(self.withdrawals_paused.read(), WITHDRAWALS_ALREADY_DISABLED);

            self.withdrawals_paused.write(false);
            self.emit(WithdrawalPausedToggled { past_value: true, new_value: false });
        }

        fn disable_withdrawals(ref self: ContractState) {
            self.roles.only_app_governor();
            assert(!self.withdrawals_paused.read(), WITHDRAWALS_ALREADY_ENABLED);

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
            self.strategy_dispatcher.read().get_available_assets_for_withdrawal()
                + self.erc20.balance_of(get_contract_address())
        }

        fn accrued_protocol_fee(self: @ContractState) -> u256 {
            self.pausable.assert_not_paused();
            let protocol_fee = self.protocol_fee.read();
            // TODO(Tomer-StarkWare): check that this optimization is good, as removing the if
            // statement doesn't affect the return value.
            if protocol_fee.is_zero() {
                return 0;
            }
            let time_delta: u64 = Time::now().sub(self.fees_updated_at.read()).into();
            // Calculate the fee based on time elapsed from last updated fee, and total
            // assets.
            u256_mul_div(
                x: protocol_fee.into(),
                y: self.erc4626.total_assets() * time_delta.into(),
                denominator: YEAR.into(),
                rounding: Rounding::Floor,
            )
                / FEE_PERCENTAGE
        }

        fn accrued_performance_fee(self: @ContractState) -> u256 {
            Default::default()
        }
    }

    #[abi(embed_v0)]
    pub impl VaultERC4626Impl of IERC4626<ContractState> {
        fn deposit(ref self: ContractState, assets: u256, receiver: ContractAddress) -> u256 {
            self.pausable.assert_not_paused();
            self.reentrancy_guard.start();
            let shares = self.erc4626.deposit(assets: assets, receiver: receiver);
            self.reentrancy_guard.end();
            shares
        }
        fn mint(ref self: ContractState, shares: u256, receiver: ContractAddress) -> u256 {
            self.pausable.assert_not_paused();
            self.reentrancy_guard.start();
            let assets = self.erc4626.mint(shares: shares, receiver: receiver);
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
            let shares = self.erc4626.withdraw(assets: assets, receiver: receiver, owner: owner);
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
            let assets = self.erc4626.redeem(shares: shares, receiver: receiver, owner: owner);
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
            let mut prev_fee = 0_u64;
            let mut prev_upper_bound = 0_u256;
            for tier in performance_fee {
                let (lower_bound, upper_bound, fee) = *tier;
                // First bound starts from 0.
                if prev_upper_bound.is_zero() {
                    assert(lower_bound.is_zero(), INVALID_LOWER_BOUND);
                } else {
                    assert(prev_upper_bound < lower_bound, INVALID_LOWER_BOUND);
                }
                assert(lower_bound < upper_bound, INVALID_UPPER_BOUND);
                assert(prev_fee < fee && fee <= MAX_BASIS_POINTS, INVALID_FEE_AMOUNT);
                self.performance_fee.push(*tier);

                prev_fee = fee;
                prev_upper_bound = upper_bound;
            }
            self.fees_updated_at.write(Time::now());
        }

        fn _take_fee(ref self: ContractState) {
            if !self.pausable.is_paused() {
                return;
            }

            let total_fee = self.accrued_protocol_fee() + self.accrued_performance_fee();
            let share_value = self
                .erc4626
                ._convert_to_assets(shares: 10_u256.pow(18), rounding: Rounding::Floor);
            let total_assets = self.erc4626.total_assets();

            let high_water_mark = self.high_water_mark.read();
            if share_value > high_water_mark {
                self.high_water_mark.write(share_value);
            }

            if total_fee.is_non_zero() && total_assets.is_non_zero() {
                let supply = self.erc20.total_supply();
                let fee_in_shares = match (supply.is_zero()) {
                    true => total_fee,
                    false => u256_mul_div(
                        x: total_fee,
                        y: supply,
                        denominator: total_assets - total_fee,
                        rounding: Rounding::Floor,
                    ),
                };

                self.erc20.mint(recipient: self.fee_recipient.read(), amount: fee_in_shares);
                self.fees_updated_at.write(Time::now());
            }
        }
    }
}


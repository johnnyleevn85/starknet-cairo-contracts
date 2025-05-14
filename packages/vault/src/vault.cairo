#[starknet::contract]
pub mod vault {
    use core::num::traits::Zero;
    use lbtc_manual_strategy::interface::IManualStrategyDispatcher;
    use lbtc_vault::errors::{
        INVALID_FEE_AMOUNT, INVALID_MAX_WITHDRAW_CALCULATIONS, INVALID_MAX_WITHDRAW_COMPRESSION,
        INVALID_PROTOCOL_FEE_CALCULATION, INVALID_SHARE_COMPRESSION,
        INVALID_TOTAL_ASSET_COMPRESSION, INVALID_ZERO_ADDRESS, INVALID_ZERO_DEPOSIT_LIMIT,
        WITHDRAWALS_ALREADY_DISABLED, WITHDRAWALS_ALREADY_ENABLED,
    };
    use lbtc_vault::events::{DepositLimitSet, FeeRecipientUpdated, WithdrawalPausedToggled};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::token::erc20::extensions::erc4626::ERC4626Component::{
        ComponentState as ERC4626ComponentState, InternalImpl,
    };
    use openzeppelin::token::erc20::extensions::erc4626::{DefaultConfig, ERC4626Component};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::utils::math::{Rounding, u256_mul_div};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::constants::DAY;
    use starkware_utils::math::utils::mul_wide_and_div;
    use starkware_utils::types::time::time::{Time, Timestamp};

    const INIT_HIGH_WATER_MARK: u128 = 1_000_000_000;
    const MAX_BASIS_POINTS: u64 = 10_000;
    // TODO(Tomer-StarkWare): move this to utils.
    const YEAR: u64 = 365 * DAY;
    const DUST: u256 = 100_000_000;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: ERC4626Component, storage: erc4626, event: ERC4626Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    /// Stores the fee values for deposit, withdraw and protocol actions
    #[derive(starknet::Store)]
    pub struct Fees {
        pub deposit_fee: u64,
        pub withdrawal_fee: u64,
        pub protocol_fee: u64,
    }

    // External

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    // TODO(Uriel): Uncomment after the implementation of all the traits and removing of the
    // duplicate functions
    // #[abi(embed_v0)]
    impl ERC4626 = ERC4626Component::ERC4626Impl<ContractState>;

    // TODO: fill the traits' functions
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
            assets
        }

        /// Adjusts withdraws within `preview_withdraw` to account for exit fees.
        /// Exit fees should be transferred in the `before_withdraw` hook.
        fn adjust_withdraw(self: @ERC4626ComponentState<ContractState>, assets: u256) -> u256 {
            let vault = self.get_contract();
            assets
        }

        /// Adjusts redeems within `preview_redeem` to account for exit fees.
        /// Exit fees should be transferred in the `before_withdraw` hook.
        fn adjust_redeem(self: @ERC4626ComponentState<ContractState>, assets: u256) -> u256 {
            let vault = self.get_contract();
            assets
        }
    }

    impl LimitConfigTraitImpl of ERC4626Component::LimitConfigTrait<ContractState> {
        fn deposit_limit(
            self: @ERC4626ComponentState<ContractState>, receiver: ContractAddress,
        ) -> Option<u256> {
            let vault = self.get_contract();
            Option::None
        }

        /// The max mint allowed.
        /// Defaults (`Option::None`) to 2 ** 256 - 1.
        fn mint_limit(
            self: @ERC4626ComponentState<ContractState>, receiver: ContractAddress,
        ) -> Option<u256> {
            let vault = self.get_contract();
            Option::None
        }

        /// The max withdraw allowed.
        /// Defaults (`Option::None`) to the full asset balance of `owner` converted from shares.
        fn withdraw_limit(
            self: @ERC4626ComponentState<ContractState>, owner: ContractAddress,
        ) -> Option<u256> {
            let vault = self.get_contract();
            Option::None
        }

        /// The max redeem allowed.
        /// Defaults (`Option::None`) to the full asset balance of `owner`.
        fn redeem_limit(
            self: @ERC4626ComponentState<ContractState>, owner: ContractAddress,
        ) -> Option<u256> {
            let vault = self.get_contract();
            Option::None
        }
    }

    impl ERC4626HooksTraitImpl of ERC4626Component::ERC4626HooksTrait<ContractState> {
        /// Hooks into `InternalImpl::_withdraw`.
        /// Executes logic before burning shares and transferring assets.
        fn before_withdraw(
            ref self: ERC4626ComponentState<ContractState>, assets: u256, shares: u256,
        ) {
            let vault = self.get_contract_mut();
        }
        /// Hooks into `InternalImpl::_deposit`.
        /// Executes logic after transferring assets and minting shares.
        fn after_deposit(
            ref self: ERC4626ComponentState<ContractState>, assets: u256, shares: u256,
        ) {
            let vault = self.get_contract_mut();
        }
    }

    impl ERC20HooksTraitImpl of ERC20Component::ERC20HooksTrait<ContractState>;

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
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        pub replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        // --- Vault ---
        token_dispatcher: IERC20Dispatcher,
        strategy_dispatcher: IManualStrategyDispatcher,
        deposit_limit: u256,
        fees_updated_at: Timestamp,
        fee_recipient: ContractAddress,
        // TODO(Mohammad): consider using pause component.
        withdrawals_paused: bool,
        high_water_mark: u128,
        pub action_fees: Fees,
        token_address: ContractAddress,
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
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);

        assert(token_address.is_non_zero(), INVALID_ZERO_ADDRESS);
        self.token_dispatcher.write(IERC20Dispatcher { contract_address: token_address });

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

        self._set_fees(:deposit_fee, :withdrawal_fee, :protocol_fee);
    }
    use lbtc_vault::interface::IVault;

    #[abi(embed_v0)]
    pub impl VaultImpl of IVault<ContractState> {
        // TODO: Implement the logic for these functions.

        /// Deposits assets into the vault for a receiver in exchange for shares.
        /// Calculates deposit fees, mints shares, transfers assets, and allocates to the strategy.
        ///
        /// # Arguments
        /// * `assets` - Amount to deposit.
        /// * `receiver` - Address to receive shares.
        ///
        /// # Returns
        /// * `shares` - Shares minted for the deposit.
        fn deposit(ref self: ContractState, assets: u256, receiver: ContractAddress) -> u256 {
            Default::default()
        }

        /// Mints shares for a receiver in exchange for assets.
        /// Calculates fee in shares, mints to fee recipient and receiver, transfers assets, and
        /// allocates to the strategy.
        ///
        /// # Arguments
        /// * `shares` - Number of shares to mint.
        /// * `receiver` - Address to receive the shares.
        ///
        /// # Returns
        /// * `assets` - Assets deposited for the minted shares.
        fn mint(ref self: ContractState, shares: u128, receiver: ContractAddress) -> u128 {
            Default::default()
        }

        /// Withdraws a specified amount of assets on behalf of an owner and sends them to a
        /// receiver.
        /// Converts assets to shares, deducts withdrawal fee, burns shares, transfers assets, and
        /// checks approval if needed.
        ///
        /// # Arguments
        /// * `assets` - Amount of assets to withdraw.
        /// * `receiver` - Address to receive the assets.
        /// * `owner` - Owner of the corresponding shares.
        ///
        /// # Returns
        /// * `shares` - Shares burned for the withdrawn assets.
        fn withdraw(
            ref self: ContractState,
            assets: u128,
            receiver: ContractAddress,
            owner: ContractAddress,
        ) -> u128 {
            50_u128
        }

        /// Redeems shares from an owner and sends assets to a receiver.
        /// Burns shares, deducts withdrawal fee, transfers assets, and checks approval if caller
        /// isn’t the owner.
        ///
        /// # Arguments
        /// * `shares` - Number of shares to redeem.
        /// * `receiver` - Address to receive the assets.
        /// * `owner` - Owner of the shares being redeemed.
        ///
        /// # Returns
        /// * `assets` - Assets returned for the redeemed shares.
        fn redeem(
            ref self: ContractState,
            shares: u128,
            receiver: ContractAddress,
            owner: ContractAddress,
        ) -> u128 {
            Default::default()
        }

        /// Returns a preview of shares that would be minted for a given asset deposit, after fees.
        fn preview_deposit(self: @ContractState, assets: u256) -> u256 {
            Default::default()
        }

        /// Returns a preview of the asset amount needed to mint a given number of shares,
        /// accounting for deposit fees.
        fn preview_mint(self: @ContractState, shares: u256) -> u256 {
            Default::default()
        }

        /// Returns a preview of the number of shares that would be burned to withdraw a given
        /// amount of assets, after fees.
        fn preview_withdraw(self: @ContractState, assets: u256) -> u256 {
            Default::default()
        }

        /// Returns a preview of the assets that would be redeemed for a given number of shares,
        /// after withdrawal fees.
        fn preview_redeem(self: @ContractState, shares: u256) -> u256 {
            Default::default()
        }

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
            ref self: ContractState, deposit_fee: u64, withdrawal_fee: u64, protocol_fee: u64,
        ) {
            self.roles.only_app_governor();
            self._set_fees(:deposit_fee, :withdrawal_fee, :protocol_fee);
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

        fn max_mint(self: @ContractState) -> u128 {
            Default::default()
        }

        fn max_withdraw(self: @ContractState, owner: ContractAddress) -> u256 {
            // Get the raw max withdrawal amount for the owner.
            let erc20 = IERC20Dispatcher { contract_address: self.token_address.read() };
            let shares = erc20.balance_of(owner).try_into().expect(INVALID_SHARE_COMPRESSION);
            let raw_max_withdraw: u128 = self
                ._convert_to_assets(:shares)
                .try_into()
                .expect(INVALID_MAX_WITHDRAW_COMPRESSION);

            // Calculate pending fees.
            let pending_fees = self.accrued_protocol_fee();

            // Return max withdraw minus pending fees.
            mul_wide_and_div(
                lhs: raw_max_withdraw,
                rhs: MAX_BASIS_POINTS.into() - self.get_withdrawal_fee().into(),
                div: MAX_BASIS_POINTS.into(),
            )
                .expect(INVALID_MAX_WITHDRAW_CALCULATIONS)
                .into()
                - pending_fees
        }

        fn get_deposit_fee(self: @ContractState) -> u64 {
            self.action_fees.deposit_fee.read()
        }

        fn get_withdrawal_fee(self: @ContractState) -> u64 {
            self.action_fees.withdrawal_fee.read()
        }

        fn get_protocol_fee(self: @ContractState) -> u64 {
            self.action_fees.protocol_fee.read()
        }

        fn get_deposit_limit(self: @ContractState) -> u256 {
            self.deposit_limit.read()
        }

        fn get_available_assets_for_withdrawal(self: @ContractState) -> u128 {
            Default::default()
        }

        fn accrued_protocol_fee(self: @ContractState) -> u256 {
            self.pausable.assert_not_paused();
            let protocol_fee: u128 = self.action_fees.protocol_fee.read().into();
            let time_delta: u64 = Time::now().sub(self.fees_updated_at.read()).into();
            match protocol_fee.is_non_zero() {
                true => {
                    // Only calculate if a protocol fee is set
                    // Calculate the fee based on time elapsed from last updated fee, and total
                    // assets.
                    // Calculations are done with u128 values as `mul_and_dev` does not support
                    // u256. As total assets cannot be larger than MAX_128, the result should fit.
                    mul_wide_and_div(
                        lhs: protocol_fee,
                        rhs: self
                            .get_total_assets()
                            .try_into()
                            .expect(INVALID_TOTAL_ASSET_COMPRESSION)
                            * time_delta.into(),
                        div: YEAR.into(),
                    )
                        .expect(INVALID_PROTOCOL_FEE_CALCULATION)
                        .into()
                        // Normalize the fee percentage
                        / 10000
                },
                false => 0,
            }
        }

        // TODO(Tomer-StarkWare): fill the following functions
        fn get_total_assets(self: @ContractState) -> u256 {
            10000000000
        }

        fn get_total_supply(self: @ContractState) -> u256 {
            10000000000
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateVault {
        fn _set_fees(
            ref self: ContractState, deposit_fee: u64, withdrawal_fee: u64, protocol_fee: u64,
        ) {
            assert(
                deposit_fee <= MAX_BASIS_POINTS
                    && withdrawal_fee <= MAX_BASIS_POINTS
                    && protocol_fee <= MAX_BASIS_POINTS,
                INVALID_FEE_AMOUNT,
            );
            self.action_fees.write(Fees { deposit_fee, withdrawal_fee, protocol_fee });
            self.fees_updated_at.write(Time::now());
        }

        fn _convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            self.erc4626._convert_to_assets(:shares, rounding: Rounding::Floor)
        }

        fn _convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            self.erc4626._convert_to_shares(:assets, rounding: Rounding::Floor)
        }

        fn _mint(ref self: ContractState, shares: u256, receiver: ContractAddress) -> u256 {
            self.erc4626.mint(:shares, :receiver)
        }
    }
}


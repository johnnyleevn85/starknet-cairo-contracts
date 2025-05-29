#[starknet::contract]
pub mod manual_strategy {
    use core::cmp::min;
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::token::erc20::extensions::erc4626::ERC4626Component::{
        ComponentState as ERC4626ComponentState, InternalImpl,
    };
    use openzeppelin::token::erc20::extensions::erc4626::{DefaultConfig, ERC4626Component};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StorageAsPointer, StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::utils::{AddToStorage, SubFromStorage};
    use crate::errors::{
        INSUFFICIENT_FUNDS, INVALID_ZERO_ADDRESS, INVALID_ZERO_AMOUNT, INVALID_ZERO_DEPOSIT_LIMIT,
        TOKEN_TRANSFER_FAILED, WITHDRAWALS_DISABLED, WITHDRAW_ALREADY_DISABLED,
        WITHDRAW_ALREADY_ENABLED,
    };
    use crate::interface::IManualStrategy;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: ERC4626Component, storage: erc4626, event: ERC4626Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);


    // External
    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;

    #[abi(embed_v0)]
    impl ERC4626 = ERC4626Component::ERC4626Impl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    #[storage]
    struct Storage {
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
        /// The address of the multi-sig contract that will be used to govern the contract.
        multi_sig_address: ContractAddress,
        /// The amount of assets deposited into this strategy.
        amount: u256,
        /// Maximum amount of the base asset that can be accumulated in the strategy.
        deposit_limit: u256,
        /// Indicates if the vault is allowed to withdraw assets from the strategy.
        withdraw_enabled: bool,
        /// The address of the contract that will receive the fees.
        fee_recipient: ContractAddress,
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
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        token_address: ContractAddress,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);

        self.erc4626.initializer(asset_address: token_address);
    }

    // TODO(Mohammad): Implement the hooks.
    impl ERC4626HooksTraitImpl of ERC4626Component::ERC4626HooksTrait<ContractState> {
        /// Hooks into `InternalImpl::_withdraw`.
        /// Executes logic before burning shares and transferring assets.
        fn before_withdraw(
            ref self: ERC4626ComponentState<ContractState>, assets: u256, shares: u256,
        ) {
            assert(assets.is_non_zero(), INVALID_ZERO_AMOUNT);
            assert(shares.is_non_zero(), INVALID_ZERO_AMOUNT);
            let mut manual_strategy = self.get_contract_mut();
            assert(manual_strategy.is_withdraw_enabled(), WITHDRAWALS_DISABLED);
            manual_strategy.amount.sub_and_write(value: assets);
            let asset_dispatcher = IERC20Dispatcher { contract_address: self.ERC4626_asset.read() };
            assert(
                asset_dispatcher
                    .transfer_from(
                        manual_strategy.multi_sig_address.read(), get_contract_address(), assets,
                    ),
                TOKEN_TRANSFER_FAILED,
            );
        }
        /// Hooks into `InternalImpl::_deposit`.
        /// Executes logic after transferring assets and minting shares.
        fn after_deposit(
            ref self: ERC4626ComponentState<ContractState>, assets: u256, shares: u256,
        ) {
            assert(assets.is_non_zero(), INVALID_ZERO_AMOUNT);
            assert(shares.is_non_zero(), INVALID_ZERO_AMOUNT);
            let mut manual_strategy = self.get_contract_mut();
            manual_strategy.amount.add_and_write(value: assets);
            let asset_dispatcher = IERC20Dispatcher { contract_address: self.ERC4626_asset.read() };
            assert(
                asset_dispatcher.transfer(manual_strategy.multi_sig_address.read(), assets),
                TOKEN_TRANSFER_FAILED,
            );
            // TODO(Tomer-StarkWare): add AssetsForwareded event
        }
    }

    impl FeeConfigTraitImpl of ERC4626Component::FeeConfigTrait<ContractState>;

    impl LimitConfigTraitImpl of ERC4626Component::LimitConfigTrait<ContractState> {
        fn deposit_limit(
            self: @ERC4626ComponentState<ContractState>, receiver: ContractAddress,
        ) -> Option<u256> {
            let manual_strategy = self.get_contract();
            Some(manual_strategy.get_deposit_limit() - manual_strategy.get_amount())
        }
    }

    impl ERC20HooksTraitImpl of ERC20Component::ERC20HooksTrait<ContractState>;

    // TODO(Gil): Implement the missing functions in the interface.
    #[abi(embed_v0)]
    pub impl ManualStrategyImpl of IManualStrategy<ContractState> {
        fn enable_withdraw(ref self: ContractState) {
            self.roles.only_security_admin();
            assert(!self.is_withdraw_enabled(), WITHDRAW_ALREADY_ENABLED);
            self.withdraw_enabled.write(true);
        }

        fn disable_withdraw(ref self: ContractState) {
            self.roles.only_security_agent();
            assert(self.is_withdraw_enabled(), WITHDRAW_ALREADY_DISABLED);
            self.withdraw_enabled.write(false);
        }

        fn update_amount(ref self: ContractState, amount: u256, is_withdrawal: bool) {
            self.roles.only_app_governor();
            let amount_ptr = self.amount.as_ptr();
            let current_amount = amount_ptr.read();
            if is_withdrawal {
                assert(current_amount >= amount, INSUFFICIENT_FUNDS);
                amount_ptr.write(current_amount - amount);
            } else {
                amount_ptr.write(current_amount + amount);
            }
        }

        fn get_available_assets_for_withdrawal(self: @ContractState) -> u256 {
            let deposited_amount = self.amount.read();
            if self.is_withdraw_enabled() {
                let balance = self.erc20.balance_of(self.multi_sig_address.read());
                min(deposited_amount, balance)
            } else {
                return deposited_amount;
            }
        }

        fn set_multi_sig(ref self: ContractState, multi_sig_address: ContractAddress) {
            self.roles.only_app_governor();
            assert(self.multi_sig_address.read().is_non_zero(), INVALID_ZERO_ADDRESS);
            self.multi_sig_address.write(multi_sig_address);
        }

        fn get_multi_sig(self: @ContractState) -> ContractAddress {
            self.multi_sig_address.read()
        }

        fn get_amount(self: @ContractState) -> u256 {
            self.amount.read()
        }

        fn is_withdraw_enabled(self: @ContractState) -> bool {
            self.withdraw_enabled.read()
        }

        fn set_deposit_limit(ref self: ContractState, new_limit: u256) {
            self.roles.only_app_governor();
            assert(new_limit.is_non_zero(), INVALID_ZERO_DEPOSIT_LIMIT);
            self.deposit_limit.write(new_limit);
        }

        fn get_deposit_limit(self: @ContractState) -> u256 {
            self.deposit_limit.read()
        }
    }
}


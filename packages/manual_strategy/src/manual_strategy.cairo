/// ⚠️ IMPORTANT ⚠️ multiSig must approve this contract to pull funds for withdrawals.
/// This contract is a strategy that forwards assets to a designated multi-signature wallet

#[starknet::contract]
pub mod manual_strategy {
    use core::cmp::min;
    use core::num::traits::Zero;
    use core::panic_with_felt252;
    use erc4626::erc4626::ERC4626Component;
    use erc4626::erc4626::ERC4626Component::{ComponentState as ERC4626ComponentState, InternalImpl};
    use erc4626::interface::IERC4626;
    use lbtc_manual_strategy::events::AssetsForwareded;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StorageAsPointer, StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::utils::{AddToStorage, SubFromStorage};
    use crate::errors::{
        INSUFFICIENT_FUNDS, INVALID_ZERO_ADDRESS, INVALID_ZERO_AMOUNT, TOKEN_TRANSFER_FAILED,
    };
    use crate::interface::IManualStrategy;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: ERC4626Component, storage: erc4626, event: ERC4626Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    impl ERC4626 = ERC4626Component::ERC4626Impl<ContractState>;

    // External
    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        erc4626: ERC4626Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        pub replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        /// The address of the multi-sig contract that will be used to govern the contract.
        multi_sig: ContractAddress,
        /// The amount of assets deposited into this strategy.
        deposited_amount: u256,
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
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        AssetsForwareded: AssetsForwareded,
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
        multi_sig: ContractAddress,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self.erc4626.initializer(asset_address: token_address);

        assert(multi_sig.is_non_zero(), INVALID_ZERO_ADDRESS);
        self.multi_sig.write(multi_sig);
    }

    impl ERC4626HooksTraitImpl of ERC4626Component::ERC4626HooksTrait<ContractState> {
        /// Hooks into `InternalImpl::_withdraw`.
        /// Executes logic before burning shares and transferring assets.
        fn before_withdraw(
            ref self: ERC4626ComponentState<ContractState>,
            assets: u256,
            shares: u256,
            fee_in_shares: u256,
        ) {
            assert(assets.is_non_zero(), INVALID_ZERO_AMOUNT);
            assert(shares.is_non_zero(), INVALID_ZERO_AMOUNT);
            let mut manual_strategy = self.get_contract_mut();
            manual_strategy.deposited_amount.sub_and_write(value: assets);
            let asset_dispatcher = IERC20Dispatcher { contract_address: self.ERC4626_asset.read() };
            assert(
                asset_dispatcher
                    .transfer_from(manual_strategy.get_multi_sig(), get_contract_address(), assets),
                TOKEN_TRANSFER_FAILED,
            );
        }
        /// Hooks into `InternalImpl::_deposit`.
        /// Executes logic after transferring assets and minting shares.
        fn after_deposit(
            ref self: ERC4626ComponentState<ContractState>,
            assets: u256,
            shares: u256,
            fee_in_shares: u256,
        ) {
            assert(assets.is_non_zero(), INVALID_ZERO_AMOUNT);
            assert(shares.is_non_zero(), INVALID_ZERO_AMOUNT);
            let mut manual_strategy = self.get_contract_mut();
            manual_strategy.deposited_amount.add_and_write(value: assets);
            let token_address = self.ERC4626_asset.read();
            let asset_dispatcher = IERC20Dispatcher { contract_address: token_address };
            let multi_sig = manual_strategy.get_multi_sig();
            assert(asset_dispatcher.transfer(multi_sig, assets), TOKEN_TRANSFER_FAILED);
            manual_strategy
                .emit(AssetsForwareded { asset_address: token_address, assets, multi_sig });
        }
    }

    impl FeeConfigTraitImpl of ERC4626Component::FeeConfigTrait<ContractState>;

    impl LimitConfigTraitImpl of ERC4626Component::LimitConfigTrait<ContractState>;

    impl ERC20HooksTraitImpl of ERC20Component::ERC20HooksTrait<ContractState>;

    impl TotalAssetCalcTraitImpl of ERC4626Component::TotalAssetCalcTrait<ContractState> {
        fn calculate_total_assets(self: @ERC4626ComponentState<ContractState>) -> u256 {
            let manual_strategy = self.get_contract();
            manual_strategy.get_deposited_amount()
        }
    }

    #[abi(embed_v0)]
    pub impl ManualStrategyImpl of IManualStrategy<ContractState> {
        fn update_amount(ref self: ContractState, amount: u256, is_withdrawal: bool) {
            self.roles.only_app_governor();
            let deposited_amount_ptr = self.deposited_amount.as_ptr();
            let current_deposited_amount = deposited_amount_ptr.read();
            if is_withdrawal {
                assert(current_deposited_amount >= amount, INSUFFICIENT_FUNDS);
                deposited_amount_ptr.write(current_deposited_amount - amount);
            } else {
                deposited_amount_ptr.write(current_deposited_amount + amount);
            }
        }

        fn get_available_assets_for_withdrawal(self: @ContractState) -> u256 {
            let deposited_amount = self.get_deposited_amount();
            let balance = self.erc20.balance_of(self.get_multi_sig());
            min(deposited_amount, balance)
        }

        fn set_multi_sig(ref self: ContractState, multi_sig: ContractAddress) {
            self.roles.only_app_governor();
            assert(multi_sig.is_non_zero(), INVALID_ZERO_ADDRESS);
            self.multi_sig.write(multi_sig);
        }

        fn get_multi_sig(self: @ContractState) -> ContractAddress {
            self.multi_sig.read()
        }

        fn get_deposited_amount(self: @ContractState) -> u256 {
            self.deposited_amount.read()
        }
    }

    #[abi(embed_v0)]
    pub impl ManualStrategyERC4626Impl of IERC4626<ContractState> {
        fn deposit(ref self: ContractState, assets: u256, receiver: ContractAddress) -> u256 {
            self.roles.only_operator();
            self.erc4626.deposit(:assets, :receiver)
        }
        fn mint(ref self: ContractState, shares: u256, receiver: ContractAddress) -> u256 {
            panic_with_felt252('MINT_NOT_SUPPORTED')
        }
        fn withdraw(
            ref self: ContractState,
            assets: u256,
            receiver: ContractAddress,
            owner: ContractAddress,
        ) -> u256 {
            self.roles.only_operator();
            self.erc4626.withdraw(:assets, :receiver, :owner)
        }
        fn redeem(
            ref self: ContractState,
            shares: u256,
            receiver: ContractAddress,
            owner: ContractAddress,
        ) -> u256 {
            panic_with_felt252('REDEEM_NOT_SUPPORTED')
        }
        fn max_deposit(self: @ContractState, receiver: ContractAddress) -> u256 {
            self.erc4626.max_deposit(:receiver)
        }
        fn max_mint(self: @ContractState, receiver: ContractAddress) -> u256 {
            panic_with_felt252('MINT_NOT_SUPPORTED')
        }
        fn max_withdraw(self: @ContractState, owner: ContractAddress) -> u256 {
            self.erc4626.max_withdraw(:owner)
        }
        fn max_redeem(self: @ContractState, owner: ContractAddress) -> u256 {
            panic_with_felt252('REDEEM_NOT_SUPPORTED')
        }
        fn preview_deposit(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.preview_deposit(:assets)
        }
        fn preview_mint(self: @ContractState, shares: u256) -> u256 {
            panic_with_felt252('MINT_NOT_SUPPORTED')
        }
        fn preview_withdraw(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.preview_withdraw(:assets)
        }
        fn preview_redeem(self: @ContractState, shares: u256) -> u256 {
            panic_with_felt252('REDEEM_NOT_SUPPORTED')
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
}


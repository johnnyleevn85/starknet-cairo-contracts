#[starknet::contract]
mod lbtc {
    use core::num::traits::Zero;
    use lbtc_token::lbtc::{errors, events};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::ERC20Component;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::interfaces::mintable_token::IMintableToken;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);


    // External
    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;

    // Internal
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        // --- Components ---
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        roles: RolesComponent::Storage,
        // --- MintableToken ---
        permitted_minters: Map<ContractAddress, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        MinterAdded: events::MinterAdded,
    }

    fn NAME() -> ByteArray {
        "Lombard Staked Bitcoin"
    }

    fn SYMBOL() -> ByteArray {
        "LBTC"
    }

    impl ImmutableConfigImpl of ERC20Component::ImmutableConfig {
        const DECIMALS: u8 = 8;
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        permitted_minters: Span<ContractAddress>,
        upgrade_delay: u64,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self.erc20.initializer(NAME(), SYMBOL());
        self._add_permitted_minters(:permitted_minters);
    }

    impl HooksImpl<> of ERC20Component::ERC20HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            self.get_contract().pausable.assert_not_paused();
        }

        fn after_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {}
    }

    #[abi(embed_v0)]
    pub impl MintableTokenImpl of IMintableToken<ContractState> {
        fn permissioned_mint(ref self: ContractState, account: ContractAddress, amount: u256) {
            self._only_permitted_minter();
            self.erc20.mint(account, amount);
        }

        fn permissioned_burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            self._only_permitted_minter();
            self.erc20.burn(account, amount);
        }

        fn is_permitted_minter(self: @ContractState, account: ContractAddress) -> bool {
            self.permitted_minters.read(account)
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn _add_permitted_minters(
            ref self: ContractState, permitted_minters: Span<ContractAddress>,
        ) {
            assert(
                0 < permitted_minters.len() && permitted_minters.len() <= 5,
                errors::INVALID_MINTERS_LIST,
            );
            for account in permitted_minters {
                assert(account.is_non_zero(), errors::INVALID_ZERO_ADDRESS);
                self.permitted_minters.write(*account, true);
                self.emit(events::MinterAdded { minter: *account });
            }
        }

        fn _only_permitted_minter(self: @ContractState) {
            let caller = get_caller_address();
            assert(self.is_permitted_minter(account: caller), errors::INVALID_MINTER);
        }
    }
}

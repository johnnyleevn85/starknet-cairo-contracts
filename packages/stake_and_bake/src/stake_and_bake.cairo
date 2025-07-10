#[starknet::contract]
pub mod stake_and_bake {
    use core::num::traits::Zero;
    use lbtc_asset_router::interface::{IAssetRouterDispatcher, IAssetRouterDispatcherTrait};
    use lbtc_consortium::interface::Signature;
    use lbtc_stake_and_bake::errors::{
        INVALID_ARRAY_LENGTH, INVALID_FEE, INVALID_ZERO_ADDRESS, MIN_MINT_NOT_MET,
        ZERO_DEPOSIT_AMOUNT,
    };
    use lbtc_stake_and_bake::events::{DepositorSet, FeeChanged};
    use lbtc_stake_and_bake::interface::IStakeAndBake;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::extensions::erc4626::interface::{
        IERC4626Dispatcher, IERC4626DispatcherTrait,
    };
    use openzeppelin::token::erc20::interface::{
        IERC20Dispatcher, IERC20DispatcherTrait, IERC20PermitDispatcher,
        IERC20PermitDispatcherTrait,
    };
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;


    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    pub const MAX_FEE: u256 = 100_000;

    #[storage]
    struct Storage {
        // --- Components ---
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        pub replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        // --- StakeAndBake ---
        token_address: ContractAddress,
        asset_router_address: ContractAddress,
        vault: ContractAddress,
        fee: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        FeeChanged: FeeChanged,
        DepositorSet: DepositorSet,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        token_address: ContractAddress,
        asset_router_address: ContractAddress,
        vault: ContractAddress,
        fee: u256,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        assert(token_address.is_non_zero(), INVALID_ZERO_ADDRESS);
        assert(asset_router_address.is_non_zero(), INVALID_ZERO_ADDRESS);

        self.token_address.write(token_address);
        self.asset_router_address.write(asset_router_address);
        self._set_depositor(:vault);
        self._set_fee(:fee);
    }

    #[abi(embed_v0)]
    pub impl StakeAndBakeImpl of IStakeAndBake<ContractState> {
        fn batch_stake_and_bake(
            ref self: ContractState,
            to_chain: Span<u256>,
            recipient: Span<ContractAddress>,
            amount: Span<u256>,
            tx_id: Span<u256>,
            vout: Span<u32>,
            proof: Span<Span<Signature>>,
            deadline: Span<u64>,
            signature: Span<Span<felt252>>,
            min_mint: Span<u256>,
        ) {
            let length = to_chain.len();
            assert(length == recipient.len(), INVALID_ARRAY_LENGTH);
            assert(length == amount.len(), INVALID_ARRAY_LENGTH);
            assert(length == tx_id.len(), INVALID_ARRAY_LENGTH);
            assert(length == vout.len(), INVALID_ARRAY_LENGTH);
            assert(length == proof.len(), INVALID_ARRAY_LENGTH);
            assert(length == deadline.len(), INVALID_ARRAY_LENGTH);
            assert(length == signature.len(), INVALID_ARRAY_LENGTH);
            assert(length == min_mint.len(), INVALID_ARRAY_LENGTH);

            for i in 0..length {
                self
                    .stake_and_bake(
                        to_chain: *to_chain[i],
                        recipient: *recipient[i],
                        amount: *amount[i],
                        tx_id: *tx_id[i],
                        vout: *vout[i],
                        proof: *proof[i],
                        deadline: *deadline[i],
                        signature: *signature[i],
                        min_mint: *min_mint[i],
                    );
            }
        }

        fn stake_and_bake(
            ref self: ContractState,
            to_chain: u256,
            recipient: ContractAddress,
            amount: u256,
            tx_id: u256,
            vout: u32,
            proof: Span<Signature>,
            deadline: u64,
            signature: Span<felt252>,
            min_mint: u256,
        ) {
            self.roles.only_token_admin();
            self.pausable.assert_not_paused();

            let fee = self.get_stake_and_bake_fee();
            assert(amount > fee, ZERO_DEPOSIT_AMOUNT);

            let asset_router = IAssetRouterDispatcher {
                contract_address: self.asset_router_address.read(),
            };
            asset_router.mint(:to_chain, :recipient, :amount, :tx_id, :vout, :proof);
            let token_address = self.token_address.read();
            let token = IERC20Dispatcher { contract_address: token_address };
            let this = get_contract_address();
            if token.allowance(owner: recipient, spender: this) < amount {
                let token_permit = IERC20PermitDispatcher { contract_address: token_address };
                token_permit
                    .permit(owner: recipient, spender: this, :amount, :deadline, :signature);
            }
            token.transfer_from(sender: recipient, recipient: this, :amount);
            if fee.is_non_zero() {
                token.transfer(recipient: asset_router.get_treasury(), amount: fee);
            }
            let vault_address = self.vault.read();
            let remaining_amount = amount - fee;
            token.approve(spender: vault_address, amount: remaining_amount);
            let vault = IERC4626Dispatcher { contract_address: vault_address };
            let shares = vault.deposit(assets: remaining_amount, receiver: recipient);
            assert(shares >= min_mint, MIN_MINT_NOT_MET);
        }

        fn set_fee(ref self: ContractState, fee: u256) {
            self.roles.only_operator();
            self._set_fee(:fee);
        }

        fn set_depositor(ref self: ContractState, vault: ContractAddress) {
            self.roles.only_app_governor();
            self._set_depositor(:vault);
        }

        fn get_stake_and_bake_depositor(self: @ContractState) -> ContractAddress {
            self.vault.read()
        }

        fn get_stake_and_bake_fee(self: @ContractState) -> u256 {
            self.fee.read()
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateAssetRouter {
        fn _set_fee(ref self: ContractState, fee: u256) {
            assert(fee <= MAX_FEE, INVALID_FEE);
            let old_fee = self.fee.read();
            self.fee.write(fee);
            self.emit(FeeChanged { old_fee, new_fee: fee });
        }

        fn _set_depositor(ref self: ContractState, vault: ContractAddress) {
            assert(vault.is_non_zero(), INVALID_ZERO_ADDRESS);
            self.vault.write(vault);
            self.emit(DepositorSet { depositor: vault });
        }
    }
}


use lbtc_vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
use lbtc_vault::tests::test_utils::*;

#[test]
fn test_vault_constructor() {
    let vault_address = init_vault_with_roles();
    let vault = IVaultDispatcher { contract_address: vault_address };

    let withdraw_result = vault.withdraw(assets: 0, receiver: vault_address, owner: vault_address);
    assert_eq!(withdraw_result, 50);

    let deposit_limit = vault.get_deposit_limit();
    assert_eq!(deposit_limit, 1000);
}

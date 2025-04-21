use lbtc_vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
use lbtc_vault::tests::test_utils::*;

#[test]
fn test_vault_constructor() {
    let vault_address = init_vault_with_roles();
    let vault = IVaultDispatcher { contract_address: vault_address };

    let foo_result = vault.foo();
    assert_eq!(foo_result, 50);
}

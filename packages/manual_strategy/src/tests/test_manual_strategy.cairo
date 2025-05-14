use lbtc_manual_strategy::interface::{IManualStrategyDispatcher, IManualStrategyDispatcherTrait};
use lbtc_manual_strategy::tests::test_utils::*;

#[test]
fn test_manual_strategy_constructor() {
    let manual_strategy_address = init_manual_strategy_with_roles();
    let manual_strategy = IManualStrategyDispatcher { contract_address: manual_strategy_address };

    let foo_result = manual_strategy.foo();
    assert_eq!(foo_result, 50);
}

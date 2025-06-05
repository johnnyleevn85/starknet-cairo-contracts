use lbtc_testing::utils::manual_strategy::*;
use crate::interface::{IManualStrategyDispatcher, IManualStrategyDispatcherTrait};
use crate::tests::test_utils::*;


#[test]
fn test_manual_strategy_constructor() {
    let manual_strategy_address = init_manual_strategy_with_roles(constants::TOKEN_ADDRESS);
    let manual_strategy = IManualStrategyDispatcher { contract_address: manual_strategy_address };

    let foo_result = manual_strategy.get_deposited_amount();
    assert_eq!(foo_result, 0);
}

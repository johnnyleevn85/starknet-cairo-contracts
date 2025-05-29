use lbtc_testing::utils::manual_strategy::*;
use starkware_utils::components::pausable::interface::{
    IPausableDispatcher, IPausableDispatcherTrait,
};
use starkware_utils_testing::constants as testing_constants;
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use crate::interface::{IManualStrategyDispatcher, IManualStrategyDispatcherTrait};
use crate::tests::test_utils::*;


#[test]
fn test_manual_strategy_constructor() {
    let manual_strategy_address = init_manual_strategy_with_roles();
    let manual_strategy = IManualStrategyDispatcher { contract_address: manual_strategy_address };

    let foo_result = manual_strategy.get_amount();
    assert_eq!(foo_result, 0);
}

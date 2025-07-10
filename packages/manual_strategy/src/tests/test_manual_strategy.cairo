use lbtc_testing::utils::manual_strategy::*;
use lbtc_testing::utils::token::init_token_with_roles;
use snforge_std::{EventSpyAssertionsTrait, spy_events};
use starkware_utils_testing::constants as testing_constants;
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use crate::interface::{IManualStrategyDispatcher, IManualStrategyDispatcherTrait};
use crate::tests::test_utils::*;


#[test]
fn test_manual_strategy_constructor() {
    let token_address = init_token_with_roles();
    let manual_strategy_address = init_manual_strategy_with_roles(:token_address);
    let manual_strategy = IManualStrategyDispatcher { contract_address: manual_strategy_address };

    let foo_result = manual_strategy.get_deposited_amount();
    assert_eq!(foo_result, 0);
}

#[test]
fn test_manual_strategy_deposit_update_amount() {
    let token_address = init_token_with_roles();
    let manual_strategy_address = init_manual_strategy_with_roles(:token_address);
    let manual_strategy = IManualStrategyDispatcher { contract_address: manual_strategy_address };

    let deposited_amount = manual_strategy.get_deposited_amount();
    assert_eq!(deposited_amount, 0);
    cheat_caller_address_once(
        contract_address: manual_strategy_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    let amount = 1_000;
    let mut spy = spy_events();
    manual_strategy.update_amount(:amount, is_withdrawal: false);
    let after_deposit_amount = manual_strategy.get_deposited_amount();

    assert_eq!(after_deposit_amount, deposited_amount + amount);
    spy
        .assert_emitted(
            @array![
                (
                    manual_strategy_address,
                    lbtc_manual_strategy::manual_strategy::manual_strategy::Event::AmountUpdated(
                        lbtc_manual_strategy::events::AmountUpdated {
                            amount,
                            is_withdrawal: false,
                            old_deposited_amount: deposited_amount,
                            new_deposited_amount: after_deposit_amount,
                        },
                    ),
                ),
            ],
        );

    cheat_caller_address_once(
        contract_address: manual_strategy_address, caller_address: testing_constants::APP_GOVERNOR,
    );
    let amount = 600;
    manual_strategy.update_amount(:amount, is_withdrawal: true);

    let after_withdrawal_amount = manual_strategy.get_deposited_amount();
    assert_eq!(after_withdrawal_amount, after_deposit_amount - amount);
    spy
        .assert_emitted(
            @array![
                (
                    manual_strategy_address,
                    lbtc_manual_strategy::manual_strategy::manual_strategy::Event::AmountUpdated(
                        lbtc_manual_strategy::events::AmountUpdated {
                            amount,
                            is_withdrawal: true,
                            old_deposited_amount: after_deposit_amount,
                            new_deposited_amount: after_withdrawal_amount,
                        },
                    ),
                ),
            ],
        );
}

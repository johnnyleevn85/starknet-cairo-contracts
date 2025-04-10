use lbtc_token::tests::test_utils::*;
use openzeppelin::token::erc20::interface::{
    IERC20Dispatcher, IERC20DispatcherTrait, IERC20MetadataDispatcher,
    IERC20MetadataDispatcherTrait,
};
use starkware_utils::components::pausable::interface::{
    IPausableDispatcher, IPausableDispatcherTrait,
};
use starkware_utils::interfaces::mintable_token::{
    IMintableTokenDispatcher, IMintableTokenDispatcherTrait,
};
use starkware_utils_testing::constants as testing_constants;
use starkware_utils_testing::test_utils::cheat_caller_address_once;


#[test]
fn test_lbtc() {
    let lbtc_address = init_token_with_roles();
    let metadata = IERC20MetadataDispatcher { contract_address: lbtc_address };
    let name = metadata.name();
    let symbol = metadata.symbol();
    let decimals = metadata.decimals();

    assert_eq!("Lombard Staked Bitcoin", name);
    assert_eq!("LBTC", symbol);
    assert_eq!(8, decimals);
}

#[test]
fn test_lbtc_mint() {
    let lbtc_address = init_token_with_roles();
    let erc20 = IERC20Dispatcher { contract_address: lbtc_address };
    let mintable = IMintableTokenDispatcher { contract_address: lbtc_address };
    let balance = erc20.balance_of(constants::PERMITTED_MINTER);
    assert_eq!(0, balance);
    let total_supply = erc20.total_supply();
    assert_eq!(0, total_supply);
    cheat_caller_address_once(lbtc_address, constants::PERMITTED_MINTER);
    mintable.permissioned_mint(testing_constants::DUMMY_ADDRESS, 1000);
    let balance = erc20.balance_of(testing_constants::DUMMY_ADDRESS);
    assert_eq!(1000, balance);
    let total_supply = erc20.total_supply();
    assert_eq!(1000, total_supply);
}

#[test]
fn test_lbtc_burn() {
    let lbtc_address = init_token_with_roles();
    let erc20 = IERC20Dispatcher { contract_address: lbtc_address };
    let mintable = IMintableTokenDispatcher { contract_address: lbtc_address };
    cheat_caller_address_once(lbtc_address, constants::PERMITTED_MINTER);
    mintable.permissioned_mint(testing_constants::DUMMY_ADDRESS, 1000);
    let balance = erc20.balance_of(testing_constants::DUMMY_ADDRESS);
    assert_eq!(1000, balance);
    let total_supply = erc20.total_supply();
    assert_eq!(1000, total_supply);
    cheat_caller_address_once(lbtc_address, constants::PERMITTED_MINTER);
    mintable.permissioned_burn(testing_constants::DUMMY_ADDRESS, 1000);
    let balance = erc20.balance_of(testing_constants::DUMMY_ADDRESS);
    assert_eq!(0, balance);
    let total_supply = erc20.total_supply();
    assert_eq!(0, total_supply);
}

#[test]
#[should_panic(expected: 'PAUSED')]
fn test_lbtc_paused() {
    let lbtc_address = init_token_with_roles();
    let mintable = IMintableTokenDispatcher { contract_address: lbtc_address };
    let pausable = IPausableDispatcher { contract_address: lbtc_address };
    cheat_caller_address_once(lbtc_address, testing_constants::SECURITY_AGENT);
    pausable.pause();
    cheat_caller_address_once(lbtc_address, constants::PERMITTED_MINTER);
    mintable.permissioned_mint(testing_constants::DUMMY_ADDRESS, 1000);
}

#[test]
#[should_panic(expected: 'INVALID_MINTER')]
fn test_lbtc_invalid_minter() {
    let lbtc_address = init_token_with_roles();
    let mintable = IMintableTokenDispatcher { contract_address: lbtc_address };
    mintable.permissioned_mint(testing_constants::DUMMY_ADDRESS, 1000);
}

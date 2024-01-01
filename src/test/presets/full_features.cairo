use core::debug::PrintTrait;
use core::zeroable::Zeroable;
use starknet::{ContractAddress, testing};
use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin::token::erc20::ERC20Component::Transfer;
use openzeppelin::access::ownable::OwnableComponent::OwnershipTransferred;

use wagmi::wagmi::interface::IHodlLimit;
use wagmi::presets::full_features::FullFeaturesContract;
use wagmi::presets::interface::{FullFeaturesABIDispatcher, FullFeaturesABIDispatcherTrait};
use wagmi::test::utils;
use wagmi::test::utils::constants;

//
// Tests
//

fn setup_dispatcher_with_event() -> FullFeaturesABIDispatcher {
    let mut calldata = array![];

    calldata.append_serde(constants::NAME);
    calldata.append_serde(constants::SYMBOL);
    calldata.append_serde(constants::SUPPLY);
    calldata.append_serde(constants::OWNER());

    // execute as owner
    testing::set_contract_address(constants::OWNER());

    // set timestamp
    testing::set_block_timestamp(constants::TIMESTAMP);

    let address = utils::deploy(FullFeaturesContract::TEST_CLASS_HASH, calldata);

    FullFeaturesABIDispatcher { contract_address: address }
}

fn setup_dispatcher() -> FullFeaturesABIDispatcher {
    let dispatcher = setup_dispatcher_with_event();

    // Drop events
    utils::drop_event(dispatcher.contract_address);

    dispatcher
}

fn setup_launched_dispatcher() -> FullFeaturesABIDispatcher {
    let dispatcher = setup_dispatcher_with_event();

    // launch
    dispatcher.launch(vesting_period: 0);

    // Drop events
    utils::drop_event(dispatcher.contract_address);

    dispatcher
}

//
// constructor
//

#[test]
#[available_gas(2000000)]
fn test_constructor() {
    let mut dispatcher = setup_dispatcher_with_event();

    dispatcher.launch(vesting_period: 0);

    assert(dispatcher.name() == constants::NAME, 'Should be NAME');
    assert(dispatcher.symbol() == constants::SYMBOL, 'Should be SYMBOL');
    assert(dispatcher.decimals() == constants::DECIMALS, 'Should be DECIMALS');
    assert(dispatcher.total_supply() == constants::SUPPLY, 'Should equal SUPPLY');
    assert(dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY, 'Should equal SUPPLY');
    assert(dispatcher.owner() == constants::OWNER(), 'Should be OWNER');

    // Check events
    assert_event_transfer(
        contract: dispatcher.contract_address,
        from: constants::ZERO(),
        to: constants::OWNER(),
        value: constants::SUPPLY
    );
    assert_event_ownership_transferred(
        contract: dispatcher.contract_address,
        previous_owner: constants::ZERO(),
        new_owner: constants::OWNER()
    );
    utils::assert_no_events_left(address: dispatcher.contract_address);
}

//
// Enable hodl limit
//

#[test]
#[available_gas(20000000)]
fn test_enable_hodl_limit() {
    let mut dispatcher = setup_launched_dispatcher();

    assert(!dispatcher.is_hodl_limit_enabled(), 'bad hodl limit status before');

    dispatcher.enable_hodl_limit();

    assert(dispatcher.is_hodl_limit_enabled(), 'bad hodl limit status after');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is the zero address', 'ENTRYPOINT_FAILED'))]
fn test_enable_hodl_limit_from_zero() {
    let mut dispatcher = setup_launched_dispatcher();

    // execute as zero
    testing::set_contract_address(constants::ZERO());

    dispatcher.enable_hodl_limit();
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn test_enable_hodl_limit_from_unauthorized() {
    let mut dispatcher = setup_launched_dispatcher();

    // execute as other
    testing::set_contract_address(constants::OTHER());

    dispatcher.enable_hodl_limit();
}

//
// Disable hodl limit
//

#[test]
#[available_gas(20000000)]
fn test_disable_hodl_limit() {
    let mut dispatcher = setup_launched_dispatcher();

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    assert(dispatcher.is_hodl_limit_enabled(), 'bad hodl limit status before');

    dispatcher.disable_hodl_limit();

    assert(!dispatcher.is_hodl_limit_enabled(), 'bad hodl limit status after');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is the zero address', 'ENTRYPOINT_FAILED'))]
fn test_disable_hodl_limit_from_zero() {
    let mut dispatcher = setup_launched_dispatcher();

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // execute as zero
    testing::set_contract_address(constants::ZERO());

    dispatcher.disable_hodl_limit();
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn test_disable_hodl_limit_from_unauthorized() {
    let mut dispatcher = setup_launched_dispatcher();

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // execute as other
    testing::set_contract_address(constants::OTHER());

    dispatcher.disable_hodl_limit();
}

//
// Add pool
//

#[test]
#[available_gas(20000000)]
fn test_add_pool() {
    let mut dispatcher = setup_launched_dispatcher();

    assert(!dispatcher.is_pool(constants::OTHER_POOL()), 'bad pool status before');

    dispatcher.add_pool(constants::OTHER_POOL());

    assert(dispatcher.is_pool(constants::OTHER_POOL()), 'bad pool status after');
}

#[test]
#[available_gas(20000000)]
fn test_add_multiple_pools() {
    let mut dispatcher = setup_launched_dispatcher();

    assert(!dispatcher.is_pool(constants::POOL()), 'bad pool status before');
    assert(!dispatcher.is_pool(constants::OTHER_POOL()), 'bad other pool status before');

    dispatcher.add_pool(constants::POOL());
    dispatcher.add_pool(constants::OTHER_POOL());

    assert(dispatcher.is_pool(constants::POOL()), 'bad pool status after');
    assert(dispatcher.is_pool(constants::OTHER_POOL()), 'bad other pool status after');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is the zero address', 'ENTRYPOINT_FAILED'))]
fn test_add_pool_from_zero() {
    let mut dispatcher = setup_launched_dispatcher();

    // execute as zero
    testing::set_contract_address(constants::ZERO());

    dispatcher.add_pool(constants::OTHER_POOL());
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn test_add_pool_from_unauthorized() {
    let mut dispatcher = setup_launched_dispatcher();

    // execute as other
    testing::set_contract_address(constants::OTHER());

    dispatcher.add_pool(constants::OTHER_POOL());
}

//
// Transfer
//

#[test]
#[available_gas(20000000)]
fn test_transfer() {
    let mut dispatcher = setup_launched_dispatcher();

    // transfer
    assert(
        dispatcher.transfer(recipient: constants::RECIPIENT(), amount: constants::VALUE),
        'Should return true'
    );

    // check balances
    assert(
        dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY - constants::VALUE,
        'Should equal SUPPLY - VALUE'
    );
    assert(dispatcher.balance_of(constants::RECIPIENT()) == constants::VALUE, 'Should equal VALUE');
}

//
// Transfer from
//

#[test]
#[available_gas(20000000)]
fn test_transfer_from() {
    let mut dispatcher = setup_launched_dispatcher();

    // approve owner to spend on himself
    dispatcher.approve(spender: constants::OWNER(), amount: constants::SUPPLY);

    // transfer
    assert(
        dispatcher
            .transfer_from(
                sender: constants::OWNER(),
                recipient: constants::RECIPIENT(),
                amount: constants::VALUE
            ),
        'Should return true'
    );

    // check balances
    assert(
        dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY - constants::VALUE,
        'Should equal SUPPLY - VALUE'
    );
    assert(dispatcher.balance_of(constants::RECIPIENT()) == constants::VALUE, 'Should equal VALUE');
}

//
// TransferFrom
//

#[test]
#[available_gas(20000000)]
fn test_transferFrom() {
    let mut dispatcher = setup_launched_dispatcher();

    // approve owner to spend on himself
    dispatcher.approve(spender: constants::OWNER(), amount: constants::SUPPLY);

    // transfer
    assert(
        dispatcher
            .transferFrom(
                sender: constants::OWNER(),
                recipient: constants::RECIPIENT(),
                amount: constants::VALUE
            ),
        'Should return true'
    );

    // check balances
    assert(
        dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY - constants::VALUE,
        'Should equal SUPPLY - VALUE'
    );
    assert(dispatcher.balance_of(constants::RECIPIENT()) == constants::VALUE, 'Should equal VALUE');
}

//
// Hodl Limit Transfer
//

#[test]
#[available_gas(20000000)]
fn test_transfer_with_hodl_limit() {
    let mut dispatcher = setup_launched_dispatcher();
    let value = constants::SUPPLY / 100; // 1%

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // renounce ownership
    dispatcher.renounce_ownership();

    // transfer
    assert(
        dispatcher.transfer(recipient: constants::RECIPIENT(), amount: value), 'Should return true'
    );

    // check balances
    assert(
        dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY - value,
        'Should equal SUPPLY - VALUE'
    );
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value, 'Should equal VALUE');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('1% Hodl limit reached', 'ENTRYPOINT_FAILED'))]
fn test_transfer_with_hodl_limit_above() {
    let mut dispatcher = setup_launched_dispatcher();
    let value = constants::SUPPLY / 100 + 1; // 1% + 1

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // renounce ownership
    dispatcher.renounce_ownership();

    // transfer
    assert(
        dispatcher.transfer(recipient: constants::RECIPIENT(), amount: value), 'Should return true'
    );
}

#[test]
#[available_gas(20000000)]
fn test_transfer_with_hodl_limit_above_from_owner() {
    let mut dispatcher = setup_launched_dispatcher();
    let value = constants::SUPPLY / 100 + 1; // 1% + 1

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // transfer
    assert(
        dispatcher.transfer(recipient: constants::RECIPIENT(), amount: value), 'Should return true'
    );

    // check balances
    assert(
        dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY - value,
        'Should equal SUPPLY - VALUE'
    );
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value, 'Should equal VALUE');
}

#[test]
#[available_gas(20000000)]
fn test_transfer_with_hodl_limit_above_to_pool() {
    let mut dispatcher = setup_launched_dispatcher();
    let value = constants::SUPPLY / 100 + 1; // 1% + 1

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // add pool
    dispatcher.add_pool(constants::POOL());

    // renounce ownership
    dispatcher.renounce_ownership();

    // transfer
    assert(dispatcher.transfer(recipient: constants::POOL(), amount: value), 'Should return true');

    // check balances
    assert(
        dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY - value,
        'Should equal SUPPLY - VALUE'
    );
    assert(dispatcher.balance_of(constants::POOL()) == value, 'Should equal VALUE');
}

//
// Hodl Limit Transfer from
//

#[test]
#[available_gas(20000000)]
fn test_transfer_from_with_hodl_limit() {
    let mut dispatcher = setup_launched_dispatcher();
    let value = constants::SUPPLY / 100; // 1%

    // approve owner to spend on himself
    dispatcher.approve(spender: constants::OWNER(), amount: constants::SUPPLY);

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // renounce ownership
    dispatcher.renounce_ownership();

    // transfer
    assert(
        dispatcher
            .transfer_from(
                sender: constants::OWNER(), recipient: constants::RECIPIENT(), amount: value
            ),
        'Should return true'
    );

    // check balances
    assert(
        dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY - value,
        'Should equal SUPPLY - VALUE'
    );
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value, 'Should equal VALUE');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('1% Hodl limit reached', 'ENTRYPOINT_FAILED'))]
fn test_transfer_from_with_hodl_limit_above() {
    let mut dispatcher = setup_launched_dispatcher();
    let value = constants::SUPPLY / 100 + 1; // 1% + 1

    // approve owner to spend on himself
    dispatcher.approve(spender: constants::OWNER(), amount: constants::SUPPLY);

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // renounce ownership
    dispatcher.renounce_ownership();

    // transfer
    assert(
        dispatcher
            .transfer_from(
                sender: constants::OWNER(), recipient: constants::RECIPIENT(), amount: value
            ),
        'Should return true'
    );
}

#[test]
#[available_gas(20000000)]
fn test_transfer_from_with_hodl_limit_above_from_owner() {
    let mut dispatcher = setup_launched_dispatcher();
    let value = constants::SUPPLY / 100 + 1; // 1% + 1

    // approve owner to spend on himself
    dispatcher.approve(spender: constants::OWNER(), amount: constants::SUPPLY);

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // transfer
    assert(
        dispatcher
            .transfer_from(
                sender: constants::OWNER(), recipient: constants::RECIPIENT(), amount: value
            ),
        'Should return true'
    );

    // check balances
    assert(
        dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY - value,
        'Should equal SUPPLY - VALUE'
    );
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value, 'Should equal VALUE');
}

#[test]
#[available_gas(20000000)]
fn test_transfer_from_with_hodl_limit_above_to_pool() {
    let mut dispatcher = setup_launched_dispatcher();
    let value = constants::SUPPLY / 100 + 1; // 1% + 1

    // approve owner to spend on himself
    dispatcher.approve(spender: constants::OWNER(), amount: constants::SUPPLY);

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // add pool
    dispatcher.add_pool(constants::POOL());

    // renounce ownership
    dispatcher.renounce_ownership();

    // transfer
    assert(
        dispatcher
            .transfer_from(sender: constants::OWNER(), recipient: constants::POOL(), amount: value),
        'Should return true'
    );

    // check balances
    assert(
        dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY - value,
        'Should equal SUPPLY - VALUE'
    );
    assert(dispatcher.balance_of(constants::POOL()) == value, 'Should equal VALUE');
}

//
// Hodl Limit TransferFrom
//

#[test]
#[available_gas(20000000)]
fn test_transferFrom_with_hodl_limit() {
    let mut dispatcher = setup_launched_dispatcher();
    let value = constants::SUPPLY / 100; // 1%

    // approve owner to spend on himself
    dispatcher.approve(spender: constants::OWNER(), amount: constants::SUPPLY);

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // renounce ownership
    dispatcher.renounce_ownership();

    // transfer
    assert(
        dispatcher
            .transferFrom(
                sender: constants::OWNER(), recipient: constants::RECIPIENT(), amount: value
            ),
        'Should return true'
    );

    // check balances
    assert(
        dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY - value,
        'Should equal SUPPLY - VALUE'
    );
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value, 'Should equal VALUE');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('1% Hodl limit reached', 'ENTRYPOINT_FAILED'))]
fn test_transferFrom_with_hodl_limit_above() {
    let mut dispatcher = setup_launched_dispatcher();
    let value = constants::SUPPLY / 100 + 1; // 1% + 1

    // approve owner to spend on himself
    dispatcher.approve(spender: constants::OWNER(), amount: constants::SUPPLY);

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // renounce ownership
    dispatcher.renounce_ownership();

    // transfer
    assert(
        dispatcher
            .transferFrom(
                sender: constants::OWNER(), recipient: constants::RECIPIENT(), amount: value
            ),
        'Should return true'
    );
}

#[test]
#[available_gas(20000000)]
fn test_transferFrom_with_hodl_limit_above_from_owner() {
    let mut dispatcher = setup_launched_dispatcher();
    let value = constants::SUPPLY / 100 + 1; // 1% + 1

    // approve owner to spend on himself
    dispatcher.approve(spender: constants::OWNER(), amount: constants::SUPPLY);

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // transfer
    assert(
        dispatcher
            .transferFrom(
                sender: constants::OWNER(), recipient: constants::RECIPIENT(), amount: value
            ),
        'Should return true'
    );

    // check balances
    assert(
        dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY - value,
        'Should equal SUPPLY - VALUE'
    );
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value, 'Should equal VALUE');
}

#[test]
#[available_gas(20000000)]
fn test_transferFrom_with_hodl_limit_above_to_pool() {
    let mut dispatcher = setup_launched_dispatcher();
    let value = constants::SUPPLY / 100 + 1; // 1% + 1

    // approve owner to spend on himself
    dispatcher.approve(spender: constants::OWNER(), amount: constants::SUPPLY);

    // enable hodl limit
    dispatcher.enable_hodl_limit();

    // add pool
    dispatcher.add_pool(constants::POOL());

    // renounce ownership
    dispatcher.renounce_ownership();

    // transfer
    assert(
        dispatcher
            .transferFrom(sender: constants::OWNER(), recipient: constants::POOL(), amount: value),
        'Should return true'
    );

    // check balances
    assert(
        dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY - value,
        'Should equal SUPPLY - VALUE'
    );
    assert(dispatcher.balance_of(constants::POOL()) == value, 'Should equal VALUE');
}

//
// Launch
//

#[test]
#[available_gas(20000000)]
fn test_launch() {
    let mut dispatcher = setup_dispatcher();

    assert(!dispatcher.launched(), 'Should not be launched');

    dispatcher.launch(vesting_period: 0);

    assert(dispatcher.launched(), 'Should be launched');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Token already launched', 'ENTRYPOINT_FAILED'))]
fn test_launch_twice() {
    let mut dispatcher = setup_dispatcher();

    dispatcher.launch(vesting_period: 0);
    dispatcher.launch(vesting_period: 0);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is the zero address', 'ENTRYPOINT_FAILED'))]
fn test_launch_from_zero() {
    let mut dispatcher = setup_dispatcher();

    // execute as zero
    testing::set_contract_address(constants::ZERO());

    dispatcher.launch(vesting_period: 0);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn test_launch_from_unauthorized() {
    let mut dispatcher = setup_dispatcher();

    // execute as other
    testing::set_contract_address(constants::OTHER());

    dispatcher.launch(vesting_period: 0);
}

//
// Mint
//

#[test]
#[available_gas(20000000)]
fn test_mint() {
    let mut dispatcher = setup_dispatcher();
    let value = constants::VALUE;

    // check balance before
    assert(dispatcher.balance_of(constants::RECIPIENT()).is_zero(), 'Should be null');

    // mint
    dispatcher.mint(recipient: constants::RECIPIENT(), amount: value);

    // launch to remove vesting balance
    dispatcher.launch(vesting_period: 0);

    // check balance after
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value, 'Should equal VALUE');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Token already launched', 'ENTRYPOINT_FAILED'))]
fn test_mint_after_launch() {
    let mut dispatcher = setup_launched_dispatcher();

    dispatcher.mint(recipient: constants::RECIPIENT(), amount: constants::VALUE);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is the zero address', 'ENTRYPOINT_FAILED'))]
fn test_mint_from_zero() {
    let mut dispatcher = setup_dispatcher();

    // execute as zero
    testing::set_contract_address(constants::ZERO());

    dispatcher.mint(recipient: constants::RECIPIENT(), amount: constants::VALUE);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn test_mint_from_unauthorized() {
    let mut dispatcher = setup_dispatcher();

    // execute as other
    testing::set_contract_address(constants::OTHER());

    dispatcher.mint(recipient: constants::RECIPIENT(), amount: constants::VALUE);
}

//
// Vested balance
//

#[test]
#[available_gas(20000000)]
fn test_vested_balance_of_before_launch() {
    let mut dispatcher = setup_dispatcher();
    let value = constants::VALUE;

    // check vested balance before
    assert(dispatcher.balance_of(constants::RECIPIENT()).is_zero(), 'Should be null');

    // mint
    dispatcher.mint(recipient: constants::RECIPIENT(), amount: value);

    // check vested balance after
    assert(dispatcher.vested_balance_of(constants::RECIPIENT()) == value, 'Should equal VALUE');
    assert(dispatcher.balance_of(constants::RECIPIENT()).is_zero(), 'Should be null');
}

#[test]
#[available_gas(20000000)]
fn test_vested_balance_of() {
    let mut dispatcher = setup_dispatcher();
    let value = 100;

    // check vested balance before
    assert(dispatcher.balance_of(constants::RECIPIENT()).is_zero(), 'Should be null');

    // mint
    dispatcher.mint(recipient: constants::RECIPIENT(), amount: value);

    // launch
    dispatcher.launch(vesting_period: 10);

    // check vested balance after
    assert(dispatcher.vested_balance_of(constants::RECIPIENT()) == value, 'Should equal VALUE');
    assert(dispatcher.balance_of(constants::RECIPIENT()).is_zero(), 'Should be null');

    // update timestamp
    testing::set_block_timestamp(constants::TIMESTAMP + 1);

    // check vested balance after
    assert(
        dispatcher.vested_balance_of(constants::RECIPIENT()) == value / 10 * 9,
        'Should equal VALUE / 10 * 9'
    );
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value / 10, 'Should be VALUE / 10');

    // update timestamp
    testing::set_block_timestamp(constants::TIMESTAMP + 5);

    // check vested balance after
    assert(
        dispatcher.vested_balance_of(constants::RECIPIENT()) == value / 2, 'Should equal VALUE / 2'
    );
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value / 2, 'Should be VALUE / 10');

    // update timestamp
    testing::set_block_timestamp(constants::TIMESTAMP + 9);

    // check vested balance after
    assert(
        dispatcher.vested_balance_of(constants::RECIPIENT()) == value / 10,
        'Should equal VALUE / 10'
    );
    assert(
        dispatcher.balance_of(constants::RECIPIENT()) == value / 10 * 9, 'Should be VALUE / 10 * 9'
    );

    // update timestamp
    testing::set_block_timestamp(constants::TIMESTAMP + 10);

    // check vested balance after
    assert(dispatcher.vested_balance_of(constants::RECIPIENT()).is_zero(), 'Should be null');
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value, 'Should be VALUE');

    // update timestamp (after vesting limit)
    testing::set_block_timestamp(constants::TIMESTAMP + 11);

    // check vested balance after
    assert(dispatcher.vested_balance_of(constants::RECIPIENT()).is_zero(), 'Should be null');
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value, 'Should be VALUE');
}

#[test]
#[available_gas(20000000)]
fn test_vested_balance_of_with_remaining() {
    let mut dispatcher = setup_dispatcher();
    let value = 5;

    // check vested balance before
    assert(dispatcher.balance_of(constants::RECIPIENT()).is_zero(), 'Should be null');

    // mint
    dispatcher.mint(recipient: constants::RECIPIENT(), amount: value);

    // launch
    dispatcher.launch(vesting_period: 10);

    // update timestamp
    testing::set_block_timestamp(constants::TIMESTAMP + 5);

    // check vested balance after
    assert(dispatcher.vested_balance_of(constants::RECIPIENT()) == 2, 'Should equal 2');
    assert(dispatcher.balance_of(constants::RECIPIENT()) == 3, 'Should equal 3');

    // update timestamp
    testing::set_block_timestamp(constants::TIMESTAMP + 6);

    // check vested balance after
    assert(dispatcher.vested_balance_of(constants::RECIPIENT()) == 2, 'Should equal 2');
    assert(dispatcher.balance_of(constants::RECIPIENT()) == 3, 'Should equal 3');
}

#[test]
#[available_gas(20000000)]
fn test_vested_balance_of_owner() {
    let mut dispatcher = setup_dispatcher();

    // check vested balance before
    assert(dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY, 'Should equal SUPPLY');
    assert(dispatcher.vested_balance_of(constants::OWNER()).is_zero(), 'Should be null');

    // launch
    dispatcher.launch(vesting_period: 10);

    // check vested balance after
    assert(dispatcher.vested_balance_of(constants::OWNER()).is_zero(), 'Should be null');
    assert(dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY, 'Should equal SUPPLY');
}

#[test]
#[available_gas(20000000)]
fn test_vested_balance_of_owner_after_mint() {
    let mut dispatcher = setup_dispatcher();
    let value = constants::VALUE;

    // check vested balance before
    assert(dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY, 'Should equal SUPPLY');
    assert(dispatcher.vested_balance_of(constants::OWNER()).is_zero(), 'Should be null');

    // mint
    dispatcher.mint(recipient: constants::OWNER(), amount: value);

    // launch
    dispatcher.launch(vesting_period: 10);

    // check vested balance after
    assert(dispatcher.vested_balance_of(constants::OWNER()).is_zero(), 'Should be null');
    assert(
        dispatcher.balance_of(constants::OWNER()) == constants::SUPPLY + value,
        'Should equal SUPPLY + VALUE'
    );
}

#[test]
#[available_gas(20000000)]
fn test_vested_balance_of_pool_after_mint() {
    let mut dispatcher = setup_dispatcher();
    let value = constants::VALUE;

    // add pool
    dispatcher.add_pool(constants::POOL());

    // check vested balance before
    assert(dispatcher.balance_of(constants::POOL()).is_zero(), 'Should be null');
    assert(dispatcher.vested_balance_of(constants::POOL()).is_zero(), 'Should be null');

    // mint
    dispatcher.mint(recipient: constants::POOL(), amount: value);

    // launch
    dispatcher.launch(vesting_period: 10);

    // check vested balance after
    assert(dispatcher.vested_balance_of(constants::POOL()).is_zero(), 'Should be null');
    assert(dispatcher.balance_of(constants::POOL()) == value, 'Should equal VALUE');
}

//
// Snapshot loader Transfer
//

#[test]
#[available_gas(20000000)]
fn test_transfer_below_vesting_limit() {
    let mut dispatcher = setup_dispatcher();
    let value = 100;

    // mint
    dispatcher.mint(recipient: constants::OTHER(), amount: value);

    // launch
    dispatcher.launch(vesting_period: 10);

    // skip some time
    testing::set_block_timestamp(constants::TIMESTAMP + 5);

    // transfer
    testing::set_contract_address(constants::OTHER());
    dispatcher.transfer(recipient: constants::RECIPIENT(), amount: value / 2);

    // check balances
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value / 2, 'Should equal VALUE / 2');
    assert(dispatcher.balance_of(constants::OTHER()).is_zero(), 'Should be zero');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Vesting limit reached', 'ENTRYPOINT_FAILED'))]
fn test_transfer_above_vesting_limit() {
    let mut dispatcher = setup_dispatcher();
    let value = 100;

    // mint
    dispatcher.mint(recipient: constants::OTHER(), amount: value);

    // launch
    dispatcher.launch(vesting_period: 10);

    // skip some time
    testing::set_block_timestamp(constants::TIMESTAMP + 5);

    // transfer
    testing::set_contract_address(constants::OTHER());
    dispatcher.transfer(recipient: constants::RECIPIENT(), amount: value / 2 + 1);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Vesting limit reached', 'ENTRYPOINT_FAILED'))]
fn test_transfer_below_vesting_limit_twice() {
    let mut dispatcher = setup_dispatcher();
    let value = 100;

    // mint
    dispatcher.mint(recipient: constants::OTHER(), amount: value);

    // launch
    dispatcher.launch(vesting_period: 10);

    // skip some time
    testing::set_block_timestamp(constants::TIMESTAMP + 5);

    // transfer
    testing::set_contract_address(constants::OTHER());
    dispatcher.transfer(recipient: constants::RECIPIENT(), amount: value / 2);
    dispatcher.transfer(recipient: constants::RECIPIENT(), amount: 1);
}

//
// Snapshot loader Transfer from
//

#[test]
#[available_gas(20000000)]
fn test_transfer_from_below_vesting_limit() {
    let mut dispatcher = setup_dispatcher();
    let value = 100;

    // mint
    dispatcher.mint(recipient: constants::OTHER(), amount: value);

    // launch
    dispatcher.launch(vesting_period: 10);

    // skip some time
    testing::set_block_timestamp(constants::TIMESTAMP + 5);

    // approve other to spend on himself
    testing::set_contract_address(constants::OTHER());
    dispatcher.approve(spender: constants::OTHER(), amount: value);

    // transfer
    dispatcher
        .transfer_from(
            sender: constants::OTHER(), recipient: constants::RECIPIENT(), amount: value / 2
        );

    // check balances
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value / 2, 'Should equal VALUE / 2');
    assert(dispatcher.balance_of(constants::OTHER()).is_zero(), 'Should be zero');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Vesting limit reached', 'ENTRYPOINT_FAILED'))]
fn test_transfer_from_above_vesting_limit() {
    let mut dispatcher = setup_dispatcher();
    let value = 100;

    // mint
    dispatcher.mint(recipient: constants::OTHER(), amount: value);

    // launch
    dispatcher.launch(vesting_period: 10);

    // skip some time
    testing::set_block_timestamp(constants::TIMESTAMP + 5);

    // approve other to spend on himself
    testing::set_contract_address(constants::OTHER());
    dispatcher.approve(spender: constants::OTHER(), amount: value);

    // transfer
    dispatcher
        .transfer_from(
            sender: constants::OTHER(), recipient: constants::RECIPIENT(), amount: value / 2 + 1
        );
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Vesting limit reached', 'ENTRYPOINT_FAILED'))]
fn test_transfer_from_below_vesting_limit_twice() {
    let mut dispatcher = setup_dispatcher();
    let value = 100;

    // mint
    dispatcher.mint(recipient: constants::OTHER(), amount: value);

    // launch
    dispatcher.launch(vesting_period: 10);

    // skip some time
    testing::set_block_timestamp(constants::TIMESTAMP + 5);

    // approve other to spend on himself
    testing::set_contract_address(constants::OTHER());
    dispatcher.approve(spender: constants::OTHER(), amount: value);

    // transfer
    dispatcher
        .transfer_from(
            sender: constants::OTHER(), recipient: constants::RECIPIENT(), amount: value / 2
        );
    dispatcher
        .transfer_from(sender: constants::OTHER(), recipient: constants::RECIPIENT(), amount: 1);
}

//
// Snapshot loader TransferFrom
//

#[test]
#[available_gas(20000000)]
fn test_transferFrom_below_vesting_limit() {
    let mut dispatcher = setup_dispatcher();
    let value = 100;

    // mint
    dispatcher.mint(recipient: constants::OTHER(), amount: value);

    // launch
    dispatcher.launch(vesting_period: 10);

    // skip some time
    testing::set_block_timestamp(constants::TIMESTAMP + 5);

    // approve other to spend on himself
    testing::set_contract_address(constants::OTHER());
    dispatcher.approve(spender: constants::OTHER(), amount: value);

    // transfer
    dispatcher
        .transferFrom(
            sender: constants::OTHER(), recipient: constants::RECIPIENT(), amount: value / 2
        );

    // check balances
    assert(dispatcher.balance_of(constants::RECIPIENT()) == value / 2, 'Should equal VALUE / 2');
    assert(dispatcher.balance_of(constants::OTHER()).is_zero(), 'Should be zero');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Vesting limit reached', 'ENTRYPOINT_FAILED'))]
fn test_transferFrom_above_vesting_limit() {
    let mut dispatcher = setup_dispatcher();
    let value = 100;

    // mint
    dispatcher.mint(recipient: constants::OTHER(), amount: value);

    // launch
    dispatcher.launch(vesting_period: 10);

    // skip some time
    testing::set_block_timestamp(constants::TIMESTAMP + 5);

    // approve other to spend on himself
    testing::set_contract_address(constants::OTHER());
    dispatcher.approve(spender: constants::OTHER(), amount: value);

    // transfer
    dispatcher
        .transferFrom(
            sender: constants::OTHER(), recipient: constants::RECIPIENT(), amount: value / 2 + 1
        );
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Vesting limit reached', 'ENTRYPOINT_FAILED'))]
fn test_transferFrom_below_vesting_limit_twice() {
    let mut dispatcher = setup_dispatcher();
    let value = 100;

    // mint
    dispatcher.mint(recipient: constants::OTHER(), amount: value);

    // launch
    dispatcher.launch(vesting_period: 10);

    // skip some time
    testing::set_block_timestamp(constants::TIMESTAMP + 5);

    // approve other to spend on himself
    testing::set_contract_address(constants::OTHER());
    dispatcher.approve(spender: constants::OTHER(), amount: value);

    // transfer
    dispatcher
        .transferFrom(
            sender: constants::OTHER(), recipient: constants::RECIPIENT(), amount: value / 2
        );
    dispatcher
        .transferFrom(sender: constants::OTHER(), recipient: constants::RECIPIENT(), amount: 1);
}

//
// Helpers
//

fn assert_event_transfer(
    contract: ContractAddress, from: ContractAddress, to: ContractAddress, value: u256
) {
    let event = utils::pop_log::<Transfer>(contract).unwrap();
    assert(event.from == from, 'Invalid `from`');
    assert(event.to == to, 'Invalid `to`');
    assert(event.value == value, 'Invalid `value`');

    // Check indexed keys
    let mut indexed_keys = array![];
    indexed_keys.append_serde(from);
    indexed_keys.append_serde(to);
    utils::assert_indexed_keys(event, indexed_keys.span());
}

fn assert_event_ownership_transferred(
    contract: ContractAddress, previous_owner: ContractAddress, new_owner: ContractAddress
) {
    let event = utils::pop_log::<OwnershipTransferred>(contract).unwrap();
    assert(event.previous_owner == previous_owner, 'Invalid `previous_owner`');
    assert(event.new_owner == new_owner, 'Invalid `new_owner`');
}

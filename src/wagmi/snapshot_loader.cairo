#[starknet::component]
mod SnapshotLoaderComponent {
    use traits::Into;
    use zeroable::Zeroable;
    use starknet::{ContractAddress, get_block_timestamp};
    use openzeppelin::token::erc20::interface::IERC20;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::token::erc20::ERC20Component::InternalTrait as ERC20InternalTrait;

    use wagmi::wagmi::interface;
    use wagmi::wagmi::interface::ISnapshotLoader;

    #[storage]
    struct Storage {
        _vested_balances: LegacyMap<ContractAddress, u256>,
        _end_of_vesting: u64,
        _vesting_period: u64,
    }

    mod Errors {
        const ALREADY_LAUNCHED: felt252 = 'Token already launched';
        const VESTING_LIMIT_REACHED: felt252 = 'Vesting limit reached';
    }

    //
    // IHodlLimit
    //

    #[embeddable_as(SnapshotLoaderImpl)]
    impl SnapshotLoader<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of interface::ISnapshotLoader<ComponentState<TContractState>> {
        fn launched(self: @ComponentState<TContractState>) -> bool {
            self._end_of_vesting.read().is_non_zero() // cannot be null if launched contrary to `_vesting_period`
        }

        fn vested_balance(self: @ComponentState<TContractState>, account: ContractAddress) -> u256 {
            let timestamp = get_block_timestamp();

            let end_of_vesting = self._end_of_vesting.read();
            let vested_balance = self._vested_balances.read(account);

            // vesting is not started yet
            if (end_of_vesting.is_zero()) {
                return vested_balance;
            }

            // vesting already passed
            if (end_of_vesting <= timestamp) {
                return 0;
            }

            // compute vested balance
            let vesting_period = self._vesting_period.read();

            let remaining_vesting = end_of_vesting - timestamp;

            return vested_balance * remaining_vesting.into() / vesting_period.into();
        }
    }

    //
    // Internals
    //

    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl ERC20: ERC20Component::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn _launch(ref self: ComponentState<TContractState>, vesting_period: u64) {
            let timestamp = get_block_timestamp();

            // check that its not already launched
            assert(!self.launched(), Errors::ALREADY_LAUNCHED);

            // start vesting
            self._end_of_vesting.write(timestamp + vesting_period);
            self._vesting_period.write(vesting_period);
        }

        fn _mint(
            ref self: ComponentState<TContractState>, recipient: ContractAddress, amount: u256
        ) {
            let mut erc20_component = get_dep_component_mut!(ref self, ERC20);

            // check token is not already launched
            assert(!self.launched(), Errors::ALREADY_LAUNCHED);

            // vest tokens
            let current_vested_balance = self._vested_balances.read(recipient);
            self._vested_balances.write(recipient, current_vested_balance + amount);

            // mint tokens
            erc20_component._mint(:recipient, :amount);
        }

        fn _check_for_vesting(ref self: ComponentState<TContractState>, account: ContractAddress) {
            let erc20_component = get_dep_component!(self, ERC20);

            let vested_balance = self.vested_balance(:account);
            let balance = erc20_component.balance_of(:account);

            assert(balance >= vested_balance, Errors::VESTING_LIMIT_REACHED);
        }
    }
}

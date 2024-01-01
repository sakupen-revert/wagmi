#[starknet::contract]
mod FullFeaturesContract {
    use wagmi::wagmi::interface::IHodlLimit;
    use starknet::ContractAddress;
    use openzeppelin::token::erc20::interface::IERC20Metadata;
    use openzeppelin::token::erc20::interface::{IERC20, IERC20CamelOnly};
    use openzeppelin::access::ownable::interface::IOwnable;
    use openzeppelin::access::ownable::ownable::OwnableComponent::InternalTrait as OwnableInternalTrait;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::access::ownable::OwnableComponent;

    use wagmi::wagmi::hodl_limit::HodlLimitComponent;
    use wagmi::wagmi::snapshot_loader::SnapshotLoaderComponent;
    use wagmi::wagmi::hodl_limit::HodlLimitComponent::InternalTrait as HodlLimitInternalTrait;
    use wagmi::wagmi::snapshot_loader::SnapshotLoaderComponent::InternalTrait as SnapshotLoaderInternalTrait;
    use wagmi::wagmi::interface::ISnapshotLoader;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: HodlLimitComponent, storage: hodl_limit, event: HodlLimitEvent);
    component!(path: SnapshotLoaderComponent, storage: snapshot_loader, event: SnapshotLoaderEvent);

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    // ERC20

    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl SafeAllowanceImpl = ERC20Component::SafeAllowanceImpl<ContractState>;
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl SafeAllowanceCamelImpl =
        ERC20Component::SafeAllowanceCamelImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    // Ownable

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableCamelOnlyImpl =
        OwnableComponent::OwnableCamelOnlyImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Hodl Limit

    #[abi(embed_v0)]
    impl HodlLimitImpl = HodlLimitComponent::HodlLimitImpl<ContractState>;
    impl HodlLimitInternalImpl = HodlLimitComponent::InternalImpl<ContractState>;

    // Hodl Limit

    #[abi(embed_v0)]
    impl SnapshotLoaderImpl =
        SnapshotLoaderComponent::SnapshotLoaderImpl<ContractState>;
    impl SnapshotLoaderInternalImpl = SnapshotLoaderComponent::InternalImpl<ContractState>;

    //
    // Storage
    //

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        hodl_limit: HodlLimitComponent::Storage,
        #[substorage(v0)]
        snapshot_loader: SnapshotLoaderComponent::Storage,
    }

    //
    // Events
    //

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        HodlLimitEvent: HodlLimitComponent::Event,
        #[flat]
        SnapshotLoaderEvent: SnapshotLoaderComponent::Event,
    }

    /// Sets the token `name` and `symbol`.
    /// Mints `fixed_supply` tokens to `recipient`.
    /// Gives contract ownership to `recipient`.
    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        fixed_supply: u256,
        recipient: ContractAddress,
    ) {
        self.erc20.initializer(name, symbol);
        self.erc20._mint(recipient, fixed_supply);
        self.ownable._transfer_ownership(recipient);
    }

    //
    // Hodl Limit
    //

    #[external(v0)]
    fn add_pool(ref self: ContractState, pool_address: ContractAddress) {
        self.ownable.assert_only_owner();

        self.hodl_limit._add_pool(:pool_address);
    }

    #[external(v0)]
    fn enable_hodl_limit(ref self: ContractState) {
        self.ownable.assert_only_owner();

        self.hodl_limit._enable_hodl_limit();
    }

    #[external(v0)]
    fn disable_hodl_limit(ref self: ContractState) {
        self.ownable.assert_only_owner();

        self.hodl_limit._disable_hodl_limit();
    }

    //
    // Snapshot Loader
    //

    #[external(v0)]
    fn launch(ref self: ContractState, vesting_period: u64) {
        self.ownable.assert_only_owner();

        self.snapshot_loader._launch(:vesting_period);
    }

    #[external(v0)]
    fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        self.ownable.assert_only_owner();

        self._mint(:recipient, :amount);
    }

    //
    // IERC20
    //

    #[external(v0)]
    impl IERC20Impl of IERC20<ContractState> {
        fn total_supply(self: @ContractState) -> u256 {
            self.erc20.total_supply()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc20.balance_of(:account) - self.vested_balance_of(:account)
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.erc20.allowance(:owner, :spender)
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = starknet::get_caller_address();

            let ret = self.erc20.transfer(:recipient, :amount);

            // hodl limit check
            self._check_hodl_limit(:sender, :recipient);

            // vesting check
            self.snapshot_loader._check_for_vesting(account: sender);

            ret
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let ret = self.erc20.transfer_from(:sender, :recipient, :amount);

            // hodl limit check
            self._check_hodl_limit(:sender, :recipient);

            // vesting check
            self.snapshot_loader._check_for_vesting(account: sender);

            ret
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.erc20.approve(:spender, :amount)
        }
    }

    #[external(v0)]
    impl IERC20CamelOnlyImpl of IERC20CamelOnly<ContractState> {
        fn totalSupply(self: @ContractState) -> u256 {
            self.erc20.totalSupply()
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc20.balanceOf(:account) - self.vested_balance_of(:account)
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let ret = self.erc20.transferFrom(:sender, :recipient, :amount);

            // hodl limit check
            self._check_hodl_limit(:sender, :recipient);

            // vesting check
            self.snapshot_loader._check_for_vesting(account: sender);

            ret
        }
    }

    //
    // Internals
    //

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _check_hodl_limit(
            ref self: ContractState, sender: ContractAddress, recipient: ContractAddress,
        ) {
            let sender_is_owner = self.ownable.owner() == sender;

            // check hodl limit
            if (!sender_is_owner) {
                self.hodl_limit._check_hodl_limit(:recipient);
            }
        }

        fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            let recipient_is_owner = self.ownable.owner() == recipient;
            let recipient_is_pool = self.is_pool(recipient);

            self
                .snapshot_loader
                ._mint(
                    with_vesting: !recipient_is_owner && !recipient_is_pool, :recipient, :amount
                );
        }
    }
}

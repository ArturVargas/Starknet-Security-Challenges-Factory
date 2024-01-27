// SPDX-License-Identifier: MIT
use starknet::ContractAddress;

#[starknet::interface]
trait IISEC<TState> {
    fn total_supply() -> u256;
    fn balance_of(account: ContractAddress) -> u256;
    fn allowance(owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(spender: ContractAddress, amount: u256) -> bool;

    // IERC20Metadata
    fn name() -> felt252;
    fn symbol() -> felt252;
    fn decimals() -> u8;

    // ISafeAllowance
    fn increase_allowance(spender: ContractAddress, added_value: u256) -> bool;
    fn decrease_allowance(spender: ContractAddress, subtracted_value: u256) -> bool;
}

#[starknet::contract]
mod InSecureumToken {
    use super::IISEC;
    use openzeppelin::token::erc20::ERC20Component;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;

    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, recipient: ContractAddress, minted_tokens: u256) {
        self.erc20.initializer('InSecureumToken', 'ISEC');

        self.erc20._mint(recipient, minted_tokens);
    }
}


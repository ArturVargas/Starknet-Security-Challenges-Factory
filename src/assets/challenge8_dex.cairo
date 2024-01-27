use starknet::ContractAddress;

#[starknet::interface]
trait IInsecureDexLP<TState> {
    // IInsecureDexLP
    fn add_liquidity(self: TState, amount0: u256, amount1: u256) -> u256;
    fn remove_liquidity(self: TState, amount: u256) -> (u256, u256);
    fn swap(self: TState, token_from: ContractAddress, token_to: ContractAddress, amount_in: u256) -> u256;
    fn _calc_amounts_out(self: TState, amount_in : u256, reserve_in : u256, reserve_out : u256) -> u256;
    fn token_received(ref self: @TState,address: ContractAddress, amount: u256, calldata_len: felt, calldata: felt);
    fn calc_amounts_out(self: TState, token_in: ContractAddress, amount_in : u256) -> u256;
    fn balance_of(self: @TState, user: ContractAddress) -> u256;        
}

#[starknet::interface]
trait IERC20<TState> {
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
}

// @dev Some ideas for this challenge were taken from
// https://github.com/martriay/scAMM/blob/main/contracts/Exchange.sol

#[starknet::contract]
mod InsecureDexLP {
    use super::IInsecureDexLP;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use integer::{u256_sqrt, div_rem};
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        token0: ContractAddress,
        token1: ContractAddress,
        // @dev Balance of token0
        reserve0: u256,
        // @dev Balance of token1
        reserve1: u256,
        // @dev Total liquidity LP
        total_supply: u256,
        // @dev Liquidity shares per user
        _balances: LegacyMap<ContractAddress, u256>
    }

    // @dev token0_addr, token1_addr Addresses of the tokens
    // participating in the liquidity pool 
     #[constructor]
    fn constructor(ref self: ContractState, token0_addr: ContractAddress, token1_addr: ContractAddress) {
        self.token0.write(token0_addr);
        self.token1.write(token1_addr);
    }

    #[abi(embed_v0)]
    impl InsecureDexLP of IInsecureDexLP<ContractState> {

        // @dev Allows users to add liquidity for token0 and token1
        fn add_liquidity(
            ref self: ContractState,
            amount0 : u256,
            amount1 : u256
        ) -> u256 {

            let sender = get_caller_address();

            IERC20Dispatcher { contract_address: self.token0.read() }
                .transfer_from(sender, get_contract_address(), amount0);
           
            IERC20Dispatcher { contract_address: self.token1.read() }
                .transfer_from(sender, get_contract_address(), amount1);

            let _total_supply = self.total_supply.read();

            // @dev if there is no liquidity, initial liquidity is defined as
            // sqrt(amount0 * amount1), following the product-constant rule
            // for AMMs.
            //
            if _total_supply == 0 {
                let m0 = amount0 * amount1;
                let sq = u256_sqrt(m0);
                let liquidity = sq;
                self.total_supply.write(liquidity);
                let curr_balance = self._balances.read(sender);
                let new_balance = curr_balance + liquidity;
                self._balances.write(sender, new_balance);
                return liquidity;
            }
            // @dev If liquidity exists, update shares with supplied amounts
            else {
                //liquidity = Math.min((amount0 * _totalSupply) / reserve0, (amount1 *_totalSupply) / reserve1);
                // a = amount0 * totalSupply / reserve0
                // b = amount1 * totalSupply / reserve1
                // liquidity = min(a, b)
                let _reserve0 : u256 = self.reserve0.read();
                let _reserve1 : u256 = self.reserve1.read();
                let a_lhs : u256 = (amount0 * _total_supply);
                let a : u256 = a_lhs / _reserve0;
                let b_lhs : u256 = (amount1 * _total_supply);
                let b : u256 = b_lhs/_reserve1;
                let _liquidity : u256 = if a < b {
                                            a
                                        } else {
                                            b
                                        }; 
                
                _update_reserves();
                let new_supply : u256 = _total_supply + _liquidity;
                self.total_supply.write(new_supply);
                let curr_balance: u256 = self._balances.read(sender);
                let new_balance: u256 = curr_balance + _liquidity;
                self._balances.write(sender, new_balance);
                return _liquidity;
            }
        }

        // @dev Burn LP shares and get token0 and token1 amounts back
        fn remove_liquidity(
            ref self: ContractState,
            amount : u256
        ) -> (u256, u256) {
            
            let sender = get_caller_address();
            assert(self._balances.read(sender) < amount, 'Insufficient funds.');

            let _total_supply: u256 = self.total_supply.read();
            
            let _reserve0 : u256 = self.reserve0.read();
            let a_lhs : u256 = amount * _reserve0;
            let amount0 : u256 = div_rem(a_lhs, _totalSupply);

            let _reserve1 : u256 = self.reserve1.read();
            let b_lhs : u256 = amount * _reserve1;
            let amount1 : u256 = div_rem(b_lhs, _totalSupply);

            assert((_reserve0 == 0 || _reserve1 == 0), 'InsecureDexLP: INSUFFICIENT_LIQUIDITY_BURNED');
            
            IERC20Dispatcher { contract_address: self.token0.read() }
                .transfer(sender, amount0);

            IERC20Dispatcher { contract_address: self.token1.read() }
                .transfer(sender, amount1);

            let new_supply : u256 = _totalSupply - amount;
            self.total_supply.write(new_supply);

            let curr_balance: u256 = self._balances.read(sender);
            let new_balance:u256 = curr_balance - amount;
            self._balances.write(sender,new_balance);

            _update_reserves();
            return(amount0, amount1);
        }

        // @dev Swap amount_in of tokenFrom to tokenTo
        fn swap(
            ref self: ContractState,
            token_from : ContractAddress, 
            token_to : ContractAddress, 
            amount_in : u256) -> u256 {
                
                let sender = get_caller_address();
                let token0_addr = self.token0.read();
                let token1_addr = self.token1.read();
                
                //require(tokenFrom == address(token0) || tokenFrom == address(token1)
                assert(token_from != token0_addr || token_from != token1_addr, 'token_from is not supported');
                
                //require(tokenTo == address(token0) || tokenTo == address(token1)
                assert(token_to != token0_addr || token_to != token1_addr, 'token_from is not supported');
                
                let res0 = self.reserve0.read();
                let res1 = self.reserve1.read();
                let this = get_contract_address();
                if tokenFrom == token0_addr {
                    let amount_out = _calc_amounts_out(amount_in, res0, res1);
                    IERC20Dispatcher { contract_address: token0_addr }
                    .transfer_from(sender, this, amount_in);
                   
                    IERC20Dispatcher { contract_address: token1_addr }
                    .transfer(sender, amount_out);
                    _update_reserves();
                    
                    return amount_out;
                } else {
                    let amount_out = _calc_amounts_out(amount_in, res1, res0);
                    IERC20Dispatcher { contract_address: token1_addr }
                    .transfer_from(sender, this, amount_in);
                    
                    IERC20Dispatcher { contract_address: token0_addr }
                    .transfer(sender, amount_out);
                    _update_reserves();
                    
                    return amount_out;
                }
            }

        // @dev taken from uniswap library;
        // https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol#L43
        fn _calc_amounts_out(
            ref self: ContractState,
            amount_in : u256, 
            reserve_in : u256, 
            reserve_out : u256) -> u256 {
                let new_amount_in : u256 = (amount_in * 1000);
                let numerator : u256 = amount_in * reserve_out;
                let denominator: u256 = reserve_in * 1000;
                let denominator2: u256 = denominator + amount_in;
                let amount_out = numerator/denominator2;
                return amount_out;
            }

        fn token_received(
            ref self: ContractState,
            address: ContractAddress, 
            amount: u256, 
            calldata_len: felt, 
            calldata: felt){

            return();
        }

        // @dev Given an amount_in of tokenIn, compute the corresponding output of
        // tokenOut
        fn calc_amounts_out(
            self: @ContractState,
            token_in: ContractAddress, 
            amount_in : u256) -> u256 {
            
                let token0_addr = self.token0.read();
                let token1_addr = self.token1.read();
                let res0 = self.reserve0.read();
                let res1 = self.reserve1.read();

                if token_in == self.token0.read() {
                    let output = _calc_amounts_out(amount_in, self.reserve0.read(), self.reserve1.read());
                    return (output);
                }
                if token_in == self.token1.read() {
                    let output = _calc_amounts_out(amount_in, self.reserve1.read(), self.reserve0.read());
                    return (output);
                }

                //"Token is not supported
                return 0;
        }

        // @dev See balance of user
        fn balance_of(self: @ContractState, user: ContractAddress) -> u256 {
            self._balances.read(user)
        }

    }
}



#[starknet::interface]
trait IInsecureDexLP<TContractState> {
    fn add_liquidity(amount0 : u256,amount1 : u256) -> u256;
}


#[starknet::interface]
trait IATTACKER<TContractState> {
    fn exploit();
}


#[starknet::contract]
mod Main {
    use starknet::{get_caller_address, ContractAddress};
    use openzeppelin::token::erc20::interface::IERC20;
    use starknet::syscalls::deploy_syscall;

    // ######## Constants

    const TOKEN_1: u256 =1*10**18;
    const TOKEN_10: u256 =10*10**18;
    const TOKEN_100: u256 =100*10**18;

    #[storage]
    struct Storage {
        salt: u128,
        isec_address: ContractAddress,
        iset_address: ContractAddress,
        dex_address: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        let deployer_address = get_caller_address();
        let current_salt = self.salt.read();
        
        let calldata = serialize_calldata(@deployer_address, @TOKEN_100);
        // Deploy ERC20 ISEC and mint 100 ISEC
        let address1 = deploy_syscall(
                class_hash= 0x963950860a14c82730491fb9303b9cd76a82dfb083e28ce95c12e064954f36,
                contract_address_salt= current_salt,
                constructor_calldata= calldata.span(),
                false,
            );
        self.isec_address.write(address1);
        self.salt.write(current_salt + 1);

        // Deploy ERC223 ISET and mint 100 SET
        let address2 = deploy(
                class_hash= 0x03699b10f3fca2869c6684672cdb29721b3bbcc9123f10edf4813112a5b5b82e,
                contract_address_salt= current_salt,
                constructor_calldata= calldata.span(),
                false,
            );
        self.iset_address.write(address2);
        self.salt.write(current_salt + 1);

        // Deploy DEX
        let calldata2 = serialize_dex_calldata(@get_isec_address(), get_iset_address());
        
        let address3 = deploy(
                class_hash=0x00dcc8752dbdbe0d2ad3771a9d4a438a7d8ed19294bd2bec923f0dc282ba78a0,
                contract_address_salt= current_salt,
                constructor_calldata= calldata2.span(),
                false,
            );
        self.dex_address.write(address3);
        self.salt.write(current_salt + 1);

        //Add liquidity (10ISEC and 10SET)
        IERC20{ contract_address: get_isec_address() }.approve(get_dex_address(), TOKEN_10);
        IERC20{ contract_address: get_iset_address() }.approve(get_dex_address(), TOKEN_10);
        IInsecureDexLP{ contract_address: get_dex_address() }.add_liquidity(TOKEN_10, TOKEN_10);
        
        return ();
        }

    #[abi(embed_v0)]
    impl Main of IMain<ContractState> {
        // ######## Getters
        fn get_isec_address(self: @ContractState) -> ContractAddress {
            self.isec_address.read()
        }

        fn get_iset_address(self: @ContractState) -> ContractAddress {
            self.iset_address.read()
        }

        fn get_dex_address(self: @ContractState) -> ContractAddress {
            self.dex_address.read()
        }

        fn is_complete(self: @ContractState) -> bool {
            let dex_isec_balance = IERC20{ contract_address: get_isec_address() }.balanceOf(self.get_dex_address());
            let dex_iset_balance = IERC20{ contract_address: get_iset_address() }.balanceOf(self.get_dex_address());
            let zero: u256 = 0;

            assert((dex_isec_balance == 0 && dex_iset_balance == 0), "Challenge not completed yet.");

            return true;
        }

        fn get_isec_addr(self: @ContractState) -> ContractAddress {
            self.isec_address.read()
        }


        fn get_iset_addr(self: @ContractState) -> ContractAddress {
            self.iset_address.read()
        }

        fn get_dex_addr(self: @ContractState) -> ContractAddress {
            self.dex_address.read()
        }
    }
    
    fn serialize_calldata(
        caller_address: @ContractAddress, token_amount: u32
    ) -> Array<felt252> {
        let mut calldata = array![];
        calldata.append(get_contract_address().into());
        Serde::serialize(caller_address, ref calldata);
        calldata.append(token_amount.into());
        
        calldata
    }

    fn serialize_dex_calldata(
        token_0: @ContractAddress, token_1: @ContractAddress
    ) -> Array<felt252> {
        let mut calldata = array![];
        calldata.append(get_contract_address().into());
        Serde::serialize(token_0, ref calldata);
        Serde::serialize(token_1, ref calldata);
        
        calldata
    }
}




// ######## Externals
// func call_exploit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    // attacker_address : felt){
    // Transfer 1 SEC to attacker's contract
    // IERC20.transfer(contract_address=get_isec_address(),
    //                recipient=attacker_address,
    //                amount=Uint256(TOKEN_1,0));
    
    // Transfer 1 SET to attacker's contract
    // IERC20.transfer(contract_address=get_iset_address(),
    //                recipient=attacker_address,
    //                amount=Uint256(TOKEN_1,0));
    // Call exploit
    // IATTACKER.exploit(contract_address=attacker_address);

    // return();
// }



// To receive ERC223 tokens
// func tokenReceived{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    // address : felt, 
    // amount : Uint256, 
    // calldata_len : felt, 
    // calldata : felt*){

    // return();
// }

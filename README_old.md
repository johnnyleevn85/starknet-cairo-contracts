How to deploy smart contract
============================

00. Decide how to provide information about deployer account

    Examples below presume that this information is available in snfoundry.toml placed into the project root directory. Name is 'new_account'.

0. Install dependencies (see README.md for details)
    It is critical to use particular version of 

    ```bash
    asdf install starknet-foundry 0.45.0
    ```

1. Manual deploy one by one (lbtc as an example)

    1.1. Declare contract

        ```bash
    sncast --account new_account declare --network sepolia --contract-name lbtc --package lbtc_token
        ```

    1.2. Deploy contract instance

        ```bash
    sncast --account new_account deploy --network sepolia --class-hash 0x01f7f91dee2ad66aa8abf779b51499468703f53efd7d382663feb540e110ce6f  --constructor-calldata 0x18fb2fcd0f285174a0aa6dc2f8b6bd3b5020ead1f90ed29e45a0e5d874121a9 0x1 0x18fb2fcd0f285174a0aa6dc2f8b6bd3b5020ead1f90ed29e45a0e5d874121a9 0x0
        ```

2. Using deployer script

        ```bash
    sncast --account new_account script run deployer --network sepolia --package deployer
        ```

or

        ```bash
    sncast --account new_account script run deployer_v2 --package deployer_v2 --url https://starknet-sepolia.public.blastapi.io/rpc/v0_8
        ```

3. Set initial ValSet (1 validator)

        ```bash
    starkli invoke --private-key <\PRIVATE KEY\> --rpc https://starknet-sepolia.public.blastapi.io/rpc/v0_8 --account <\PATH TO ACCOUNT DATA\> <\ADDRESS OF CONSORTIUM CONTRACT\> set_initial_validator_set 1 1 u256:0x7215b625eecb2252733f2700085b6cbd59af02c24ed192e08eda7c29d19bc48c u256:0xdaa795708209fe648a85145e86e1d3b3d6544f7f519f26b5451f6a27e1864e83 1 1 1
        ```

4. Set next ValSet (4 validators, threshold 4, height 7, 1 signature)
        ```bash
    starkli invoke --private-key <\PRIVATE KEY\> --rpc https://starknet-sepolia.public.blastapi.io/rpc/v0_8 --account <\PATH TO ACCOUNT DATA\> <\ADDRESS OF CONSORTIUM CONTRACT\> set_next_validator_set 2 4 u256:0x663730d52c5ae76aa45189e3a007240da11fca011a6ed9eb427ddcd72a806114 u256:0x48f1dc776b895b5c7ab2914437f255b2002001821d271ca9aa2bed6819078c1e u256:0x7215b625eecb2252733f2700085b6cbd59af02c24ed192e08eda7c29d19bc48c u256:0xdaa795708209fe648a85145e86e1d3b3d6544f7f519f26b5451f6a27e1864e83 u256:0x1ea483b4bc14192b3ff4b7ee9659df83242782ee7c6a9ef5dea22b98c25e9c0c u256:0xea1cabc05e2592e52d6a35b95a357f35931444e19829de42388d3769d56a285c u256:0xa000197aa21edf43895e52501fdeebaa52c618fe5cc0dc05e485f53b51199322 u256:0x7bf7fe2944bdd230ced14bcacfff732aad635bd67d2e0cdb760d73b06bf8d3dd 4 1 1 1 1 4 7 1 u256:0xdc176347b9bb76b1caf1eac6ab73ac5c9fd225675b6658b132652f5813dd9cdc u256:0x3c2b3d2c3c9095b2ef0f162b20e9a60828ceb43a1f3e44fd353b59e9b948278d
        ```
5. Smart contract upgrade (presumes that the new class for the contract has been declared and class hash is available)
    Should be done in two steps:
    - add new implementation

        ```bash
    starkli invoke --private-key <\PRIVATE KEY\> --rpc https://starknet-sepolia.public.blastapi.io/rpc/v0_8 --account <\PRIVATE KEY\> <\CONTRACT ADDRESS\> add_new_implementation <\NEW IMPLEMENTATION CLASS HASH\> 1 0        
        ```

    - replace to it
        ```bash
    starkli invoke --private-key <\PRIVATE KEY\> --rpc https://starknet-sepolia.public.blastapi.io/rpc/v0_8 --account <\PRIVATE KEY\> <\CONTRACT ADDRESS\> replace_to <\NEW IMPLEMENTATION CLASS HASH\> 1 0
        ```

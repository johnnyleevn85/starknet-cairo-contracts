How to deploy smart contract
============================

0. Decide how to provide information about deployer account

    Examples below presume that this information is available in snfoundry.toml placed into the project root directory. Name is 'new_account'.

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

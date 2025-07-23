from starknet_py.proxy.contract_abi_resolver import ContractAbiResolver, ProxyConfig

import pytest_asyncio
from starknet_py.contract import Contract
from starknet_test_util import StarknetTestUtils, load_contract, grant_roles

LBTC_STAKE_AND_BAKE = "lbtc_stake_and_bake_stake_and_bake"
ROLE_NAMES = [
    "governance_admin",
    "upgrade_governor",
    "app_role_admin",
    "app_governor",
    "operator",
    "token_admin",
    "security_admin",
    "security_agent",
    "user",
    "token_address",
]


@pytest_asyncio.fixture
async def stake_and_bake_test_context(starknet_test_utils: StarknetTestUtils) -> dict:
    roles = {name: starknet_test_utils.accounts[i] for i, name in enumerate(ROLE_NAMES)}

    compiled_contract_casm = load_contract(f"{LBTC_STAKE_AND_BAKE}.compiled_contract_class")
    compiled_contract = load_contract(f"{LBTC_STAKE_AND_BAKE}.contract_class")
    declare_result = await Contract.declare_v3(
        account=roles["governance_admin"],
        compiled_contract=compiled_contract,
        compiled_contract_casm=compiled_contract_casm,
        auto_estimate=True,
    )
    await declare_result.wait_for_acceptance(check_interval=0.1)

    deploy_result = await declare_result.deploy_v3(
        auto_estimate=True,
        constructor_args=[
            roles["governance_admin"].address,
            30,  # initial_upgrade_delay
            roles["token_address"].address,
            roles["user"].address,  # user is the multi sig.
        ],
    )
    await deploy_result.wait_for_acceptance(check_interval=0.1)
    contract = deploy_result.deployed_contract

    abi, cairo_version = await ContractAbiResolver(
        address=contract.address,
        client=contract.client,
        proxy_config=ProxyConfig(),
    ).resolve()

    contracts_by_role = {
        role: Contract(
            address=contract.address, abi=abi, provider=account, cairo_version=cairo_version
        )
        for role, account in roles.items()
    }

    await grant_roles(contracts_by_role=contracts_by_role, roles=roles)
    return {
        "contract": contract,
        "contracts_by_role": contracts_by_role,
        "roles": roles,
    }

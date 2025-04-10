from starknet_py.proxy.contract_abi_resolver import ContractAbiResolver, ProxyConfig

import pytest_asyncio
from starknet_py.contract import Contract
from starknet_net_test_util import StarknetTestUtils, load_contract

LBTC_BASCULE = "lbtc_bascule_bascule"
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
    "validation_consumer",
]


@pytest_asyncio.fixture(scope="session")
async def bascule_test_context(starknet_test_utils: StarknetTestUtils) -> dict:
    roles = {name: starknet_test_utils.accounts[i] for i, name in enumerate(ROLE_NAMES)}

    compiled_contract_casm = load_contract(f"{LBTC_BASCULE}.compiled_contract_class")
    compiled_contract = load_contract(f"{LBTC_BASCULE}.contract_class")
    declare_result = await Contract.declare_v3(
        account=roles["governance_admin"],
        compiled_contract=compiled_contract,
        compiled_contract_casm=compiled_contract_casm,
        auto_estimate=True,
    )
    await declare_result.wait_for_acceptance()

    deploy_result = await declare_result.deploy_v3(
        auto_estimate=True,
        constructor_args=[
            roles["governance_admin"].address,
            30,  # initial_upgrade_delay
            50,  # initial_max_deposits
            roles["validation_consumer"].address,
        ],
    )
    await deploy_result.wait_for_acceptance()
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

    # Grant roles
    await (
        await contracts_by_role["governance_admin"]
        .functions["register_app_role_admin"]
        .invoke_v3(roles["app_role_admin"].address, auto_estimate=True)
    ).wait_for_acceptance()

    await (
        await contracts_by_role["governance_admin"]
        .functions["register_upgrade_governor"]
        .invoke_v3(roles["upgrade_governor"].address, auto_estimate=True)
    ).wait_for_acceptance()

    await (
        await contracts_by_role["governance_admin"]
        .functions["register_security_admin"]
        .invoke_v3(roles["security_admin"].address, auto_estimate=True)
    ).wait_for_acceptance()

    await (
        await contracts_by_role["app_role_admin"]
        .functions["register_app_governor"]
        .invoke_v3(roles["app_governor"].address, auto_estimate=True)
    ).wait_for_acceptance()

    await (
        await contracts_by_role["app_role_admin"]
        .functions["register_operator"]
        .invoke_v3(roles["operator"].address, auto_estimate=True)
    ).wait_for_acceptance()

    await (
        await contracts_by_role["app_role_admin"]
        .functions["register_token_admin"]
        .invoke_v3(roles["token_admin"].address, auto_estimate=True)
    ).wait_for_acceptance()

    await (
        await contracts_by_role["security_admin"]
        .functions["register_security_agent"]
        .invoke_v3(roles["security_agent"].address, auto_estimate=True)
    ).wait_for_acceptance()

    return {
        "contract": contract,
        "contracts_by_role": contracts_by_role,
        "roles": roles,
    }

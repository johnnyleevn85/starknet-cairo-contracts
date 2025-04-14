from starknet_py.proxy.contract_abi_resolver import ContractAbiResolver, ProxyConfig

import pytest_asyncio
from starknet_py.contract import Contract
from starknet_net_test_util import StarknetTestUtils, load_contract

LBTC_CONSORTIUM = "lbtc_consortium_consortium"
ROLE_NAMES = [
    "governance_admin",
    "upgrade_governor",
    "app_role_admin",
    "app_governor",
    "operator",
    "token_admin",
    "security_admin",
    "security_agent",
    "user_1",
    "user_2",
]


@pytest_asyncio.fixture(scope="session")
async def consortium_test_context(starknet_test_utils: StarknetTestUtils) -> dict:
    roles = {name: starknet_test_utils.accounts[i] for i, name in enumerate(ROLE_NAMES)}

    compiled_contract_casm = load_contract(f"{LBTC_CONSORTIUM}.compiled_contract_class")
    compiled_contract = load_contract(f"{LBTC_CONSORTIUM}.contract_class")

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
            50,  # initial_upgrade_delay
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
    for role_name in ["app_role_admin", "upgrade_governor", "security_admin"]:
        await (
            await contracts_by_role["governance_admin"]
            .functions[f"register_{role_name}"]
            .invoke_v3(roles[role_name].address, auto_estimate=True)
        ).wait_for_acceptance()

    for role_name in ["app_governor", "operator", "token_admin"]:
        await (
            await contracts_by_role["app_role_admin"]
            .functions[f"register_{role_name}"]
            .invoke_v3(roles[role_name].address, auto_estimate=True)
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

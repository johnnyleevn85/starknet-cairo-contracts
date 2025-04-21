from starknet_py.proxy.contract_abi_resolver import ContractAbiResolver, ProxyConfig

import pytest_asyncio
from starknet_py.contract import Contract
from starknet_net_test_util import StarknetTestUtils, load_contract, grant_roles

LBTC_BRIDGE = "lbtc_bridge_bridge"
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
async def bridge_test_context(starknet_test_utils: StarknetTestUtils) -> dict:
    roles = {name: starknet_test_utils.accounts[i] for i, name in enumerate(ROLE_NAMES)}

    compiled_contract_casm = load_contract(f"{LBTC_BRIDGE}.compiled_contract_class")
    compiled_contract = load_contract(f"{LBTC_BRIDGE}.contract_class")
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
            roles["governance_admin"].address,  # TODO change to lbtc_token
            roles["governance_admin"].address,  # TODO change to bascule
            roles["governance_admin"].address,  # TODO change to consortium
            roles["governance_admin"].address,  # TODO change to treasury
            1,  # initial_burn_commission
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

    await grant_roles(contracts_by_role=contracts_by_role, roles=roles)
    return {
        "contract": contract,
        "contracts_by_role": contracts_by_role,
        "roles": roles,
    }

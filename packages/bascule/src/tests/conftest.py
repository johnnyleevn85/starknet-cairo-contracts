from starknet_py.proxy.contract_abi_resolver import ContractAbiResolver, ProxyConfig

import pytest_asyncio
from starknet_py.contract import Contract
from test_utils.starknet_test_utils import StarknetTestUtils, load_contract, grant_roles
import os
from pathlib import Path
from scripts.script_utils import get_project_root


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
    "pauser",
    "deposit_reporter",
    "withdrawal_validator",
]

ROLES = None  # Initialize global variable


@pytest_asyncio.fixture(autouse=True)
async def setup_global_roles(starknet_test_utils: StarknetTestUtils):
    global ROLES
    ROLES = {name: starknet_test_utils.accounts[i] for i, name in enumerate(ROLE_NAMES)}


@pytest_asyncio.fixture
async def bascule_declaration_context() -> dict:
    # Declaration part - done once per session
    compiled_contract_casm = load_contract(
        contract_name=f"{LBTC_BASCULE}.compiled_contract_class",
        base_path=Path(os.path.join(get_project_root(), "target", "dev")),
    )
    compiled_contract = load_contract(
        contract_name=f"{LBTC_BASCULE}.contract_class",
        base_path=Path(os.path.join(get_project_root(), "target", "dev")),
    )
    declare_result = await Contract.declare_v3(
        account=ROLES["governance_admin"],
        compiled_contract=compiled_contract,
        compiled_contract_casm=compiled_contract_casm,
        auto_estimate=True,
    )
    await declare_result.wait_for_acceptance(check_interval=0.1)

    return {
        "declare_result": declare_result,
    }


@pytest_asyncio.fixture(scope="function")
async def bascule_test_context(bascule_declaration_context: dict) -> dict:
    declare_result = bascule_declaration_context["declare_result"]

    # Deployment part - fresh for each test
    deploy_result = await declare_result.deploy_v3(
        auto_estimate=True,
        constructor_args=[
            ROLES["governance_admin"].address,
            ROLES["pauser"].address,
            ROLES["deposit_reporter"].address,
            ROLES["withdrawal_validator"].address,
            50,  # initial_max_deposits
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
            address=contract.address,
            abi=abi,
            provider=account,
            cairo_version=cairo_version,
        )
        for role, account in ROLES.items()
    }

    return {
        "contract": contract,
        "contracts_by_role": contracts_by_role,
    }

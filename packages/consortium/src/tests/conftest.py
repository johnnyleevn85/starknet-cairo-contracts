import pytest_asyncio
import pytest

from starknet_net_test_util import StarknetTestUtils

from starknet_py.contract import Contract
from starknet_py.net.account.account import Account

from starknet_net_test_util import load_contract


@pytest_asyncio.fixture(scope="session")
def governance_admin(starknet_test_utils: StarknetTestUtils) -> Account:
    return starknet_test_utils.accounts[0]


@pytest_asyncio.fixture(scope="session")
async def consortium_contract(
    starknet_test_utils: StarknetTestUtils, governance_admin: Account
) -> Contract:
    compiled_contract_casm = load_contract("lbtc_consortium_consortium.compiled_contract_class")
    compiled_contract = load_contract("lbtc_consortium_consortium.contract_class")

    declare_result = await Contract.declare_v3(
        starknet_test_utils.accounts[0],
        compiled_contract=compiled_contract,
        compiled_contract_casm=compiled_contract_casm,
        auto_estimate=True,
    )
    await declare_result.wait_for_acceptance()
    deploy_result = await declare_result.deploy_v3(
        auto_estimate=True, constructor_args=[governance_admin.address, 50]
    )
    await deploy_result.wait_for_acceptance()
    return deploy_result.deployed_contract

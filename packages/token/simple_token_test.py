import pytest
from starknet_net_test_util import StarknetTestUtils

from starknet_py.contract import Contract
from starknet_net_test_util import load_contract


@pytest.mark.asyncio
async def test_foo(starknet_test_utils: StarknetTestUtils):
    compiled_contract_casm = load_contract("lbtc_bascule_bascule.compiled_contract_class")
    compiled_contract = load_contract("lbtc_bascule_bascule.contract_class")

    declare_result = await Contract.declare_v3(
        starknet_test_utils.accounts[0],
        compiled_contract=compiled_contract,
        compiled_contract_casm=compiled_contract_casm,
        auto_estimate=True,
    )
    await declare_result.wait_for_acceptance()
    deploy_result = await declare_result.deploy_v3(auto_estimate=True, constructor_args=[0x5, 50])
    await deploy_result.wait_for_acceptance()
    contract = deploy_result.deployed_contract
    (res,) = await contract.functions["get_max_deposits"].call()

    assert res == 50

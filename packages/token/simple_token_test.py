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
    assert True

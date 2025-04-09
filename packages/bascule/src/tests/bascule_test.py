import pytest
from starknet_py.contract import Contract


@pytest.mark.asyncio
async def test_get_max_deposits(bascule_contract: Contract):
    (res,) = await bascule_contract.functions["get_max_deposits"].call()
    assert res == 50

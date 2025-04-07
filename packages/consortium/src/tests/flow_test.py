import pytest
from starknet_py.contract import Contract


@pytest.mark.asyncio
async def test_get_current_epoch(consortium_contract: Contract):
    (res,) = await consortium_contract.functions["get_current_epoch"].call()
    assert res == 0

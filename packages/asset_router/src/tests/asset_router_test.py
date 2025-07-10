import pytest


@pytest.mark.asyncio
async def test_get_dust_fee_rate(asset_router_test_context: dict):
    user = asset_router_test_context["contracts_by_role"]["user"]

    (res,) = await user.functions["get_dust_fee_rate"].call()
    assert res == 3000

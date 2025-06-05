import pytest


@pytest.mark.asyncio
async def test_foo(manual_strategy_test_context: dict):
    user = manual_strategy_test_context["contracts_by_role"]["user"]

    (res,) = await user.functions["get_deposited_amount"].call()
    assert res == 0

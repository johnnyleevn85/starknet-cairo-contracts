import pytest


@pytest.mark.asyncio
async def test_foo(manual_strategy_test_context: dict):
    user = manual_strategy_test_context["contracts_by_role"]["user"]

    (res,) = await user.functions["foo"].call()
    assert res == 50

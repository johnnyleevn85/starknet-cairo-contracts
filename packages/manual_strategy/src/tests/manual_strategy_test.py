import pytest


@pytest.mark.asyncio
@pytest.mark.skip(reason="no need to test this")
async def test_foo(manual_strategy_test_context):
    user = manual_strategy_test_context["contracts_by_role"]["user"]

    (res,) = await user.functions["get_deposited_amount"].call()
    assert res == 0

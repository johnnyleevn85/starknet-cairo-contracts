import pytest
from starknet_py.contract import Contract


@pytest.mark.asyncio
async def test_get_max_deposits(bascule_test_context: dict):
    user = bascule_test_context["contracts_by_role"]["user"]

    (res,) = await user.functions["get_max_deposits"].call()
    assert res == 50


@pytest.mark.asyncio
async def test_set_max_deposits(bascule_test_context: dict):
    user = bascule_test_context["contracts_by_role"]["user"]
    (res,) = await user.functions["get_max_deposits"].call()
    assert res == 50

    app_governor = bascule_test_context["contracts_by_role"]["app_governor"]

    invocation = await app_governor.functions["set_max_deposits"].invoke_v3(
        15,
        auto_estimate=True,
    )
    await invocation.wait_for_acceptance()

    (res,) = await user.functions["get_max_deposits"].call()
    assert res == 15

    invocation = await app_governor.functions["set_max_deposits"].invoke_v3(
        50,
        auto_estimate=True,
    )
    await invocation.wait_for_acceptance()

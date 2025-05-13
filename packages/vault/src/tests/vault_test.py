import pytest


@pytest.mark.asyncio
async def test_withdraw(vault_test_context: dict):
    user = vault_test_context["contracts_by_role"]["user"]
    assets = 20
    receiver = 50
    owner = 100

    await user.functions["withdraw"].invoke_v3(assets, receiver, owner, auto_estimate=True)
    # TODO(Tomer-StarkWare): Check the result.


@pytest.mark.asyncio
async def test_get_deposit_limit(vault_test_context: dict):
    user = vault_test_context["contracts_by_role"]["user"]

    (res,) = await user.functions["get_deposit_limit"].call()
    assert res == 1000

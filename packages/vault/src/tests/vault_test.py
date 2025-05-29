import pytest


@pytest.mark.asyncio
async def test_get_deposit_limit(vault_test_context: dict):
    user = vault_test_context["contracts_by_role"]["user"]

    (res,) = await user.functions["get_deposit_limit"].call()
    assert res == 1000

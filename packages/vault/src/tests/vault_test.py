import pytest


@pytest.mark.asyncio
async def test_foo(vault_test_context: dict):
    user = vault_test_context["contracts_by_role"]["user"]

    (res,) = await user.functions["foo"].call()
    assert res == 50

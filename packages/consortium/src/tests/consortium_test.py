import pytest
from starknet_py.contract import Contract


@pytest.mark.asyncio
async def test_get_current_epoch(consortium_test_context: dict):
    user = consortium_test_context["contracts_by_role"]["user_1"]

    (res,) = await user.functions["get_current_epoch"].call()
    assert res == 0
    app_governor = consortium_test_context["contracts_by_role"]["app_governor"]
    await (
        await app_governor.functions["set_initial_validator_set"].invoke_v3(
            [{"address": 20}, {"address": 30}, {"address": 40}], [5, 5, 5], 10, auto_estimate=True
        )
    ).wait_for_acceptance()

    (res,) = await user.functions["get_current_epoch"].call()
    assert res == 1
